#!/usr/bin/env python3
"""Deploy decision logic for the stop tiles workflow (standard library only).

The GitHub Actions workflow calls these subcommands so that every decision can
be exercised locally. Machine-readable results are ``key=value`` lines on
stdout (the workflow appends them to ``$GITHUB_OUTPUT``); human-readable
messages go to stderr. The script never touches the network and never reads
the Metro API key.

Subcommands
-----------
classify-deployed --http-code CODE
    Result of fetching the deployed ``meta.json``: 200 -> ``present=true``,
    404 -> ``present=false`` (first deploy); anything else fails the run.

plan-fetch --deployed PATH [--force true|false]
    Decide whether the ``gtfs.zip`` request is conditional. It is conditional
    (``mode=conditional``, ``if_none_match=<deployed e>``) only when a usable
    deployed meta with an ETag exists, ``force`` is not set and the deployed
    ``gv`` equals this generator's GENERATOR_VERSION. Otherwise it is
    unconditional (``mode=unconditional``).

classify-fetch --http-code CODE --conditional true|false [--file PATH]
    200 -> ``result=download`` (and ``PATH``, if given, must be a zip);
    304 -> ``result=unchanged`` and only when the request was conditional;
    anything else fails the run.

etag HEADER_FILE
    Print ``etag=<value>`` for the ETag in a curl ``--dump-header`` file (the
    last response block wins); the value is empty when there is none.

decide --new PATH --deployed PATH [--force true|false]
       [--max-drop-percent P] [--min-stops N]
    Sanity-check the freshly generated meta.json, then decide whether to
    deploy (``deploy=true|false`` and ``reason=<token>``). Sanity failures
    exit non-zero and are never overridden by ``force``.

A ``--deployed`` path that does not exist means there is no deployed site yet
(first deploy). A deployed meta.json that cannot be parsed, or that has no
integer ``n``, is reported on stderr and treated as having no baseline, so a
later deploy can repair it; the absolute floor still applies.
"""

import argparse
import json
import os
import re
import sys
import zipfile
from fractions import Fraction

from generate_tiles import GENERATOR_VERSION

DEFAULT_MAX_DROP_PERCENT = "10"
DEFAULT_MIN_STOPS = "1800"

# RFC 9110 entity-tag, restricted to printable ASCII so it is safe in a header.
_ETAG_RE = re.compile(r'(W/)?"[\x21\x23-\x7e]*"', re.ASCII)
_HEADER_RE = re.compile(r"^etag[ \t]*:[ \t]*(.*?)[ \t]*$", re.IGNORECASE)


class DecisionError(Exception):
    """A condition that must fail the workflow run with a clear message."""


def parse_bool(text):
    value = (text or "").strip().lower()
    if value in ("true", "1", "yes"):
        return True
    if value in ("false", "0", "no", ""):
        return False
    raise DecisionError("not a boolean: %r" % text)


def _is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def load_deployed(path):
    """Return the deployed meta dict, or None when there is no usable one."""
    if path is None or not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as handle:
            meta = json.load(handle)
    except (OSError, ValueError) as error:
        print("warning: deployed meta.json is unreadable (%s); "
              "treating it as having no baseline" % error, file=sys.stderr)
        return None
    if not isinstance(meta, dict):
        print("warning: deployed meta.json is not a JSON object; "
              "treating it as having no baseline", file=sys.stderr)
        return None
    return meta


def load_new(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            meta = json.load(handle)
    except (OSError, ValueError) as error:
        raise DecisionError("new meta.json is unreadable: %s" % error)
    if (not isinstance(meta, dict) or not _is_int(meta.get("n"))
            or not _is_int(meta.get("gv")) or not isinstance(meta.get("h"), str)):
        raise DecisionError("new meta.json lacks integer n/gv or string h")
    return meta


def classify_deployed(http_code):
    if http_code == 200:
        return "present"
    if http_code == 404:
        return "absent"
    raise DecisionError("unexpected HTTP status %d fetching the deployed meta.json"
                        % http_code)


def plan_fetch(deployed, force):
    """Return (conditional, if_none_match, reason)."""
    if force:
        return False, "", "force"
    if deployed is None:
        return False, "", "no-deployed-meta"
    if deployed.get("gv") != GENERATOR_VERSION:
        return False, "", "generator-version-changed"
    etag = deployed.get("e")
    if not isinstance(etag, str) or not etag.strip():
        return False, "", "no-deployed-etag"
    etag = etag.strip()
    if not _valid_etag(etag):
        return False, "", "invalid-deployed-etag"
    return True, etag, "conditional"


def _valid_etag(etag):
    return _ETAG_RE.fullmatch(etag) is not None


def classify_fetch(http_code, conditional, path=None):
    if http_code == 304:
        if not conditional:
            raise DecisionError("HTTP 304 for an unconditional request")
        return "unchanged"
    if http_code == 200:
        if path is not None and not zipfile.is_zipfile(path):
            raise DecisionError("HTTP 200 body is not a zip file")
        return "download"
    raise DecisionError("unexpected HTTP status %d fetching gtfs.zip" % http_code)


def extract_etag(text):
    """The ETag of the last response block in a curl --dump-header file."""
    etag = ""
    for line in text.splitlines():
        if line.startswith("HTTP/"):
            etag = ""  # a new response block starts
            continue
        match = _HEADER_RE.match(line)
        if match:
            value = match.group(1)
            etag = value if _valid_etag(value) else ""
    return etag


def parse_threshold(max_drop_percent, min_stops):
    try:
        percent = Fraction(str(max_drop_percent).strip())
    except (ValueError, ZeroDivisionError):
        raise DecisionError("max drop percent is not a number: %r" % max_drop_percent)
    if not 0 <= percent <= 100:
        raise DecisionError("max drop percent must be 0..100, got %s" % max_drop_percent)
    text = str(min_stops).strip()
    if not (text.isascii() and text.isdigit()):
        raise DecisionError("minimum stop count must be a non-negative integer: %r"
                            % min_stops)
    return percent, int(text)


def decide(new, deployed, force, max_drop_percent=DEFAULT_MAX_DROP_PERCENT,
           min_stops=DEFAULT_MIN_STOPS):
    """Return (deploy, reason). Raises DecisionError when the sanity check fails."""
    percent, floor = parse_threshold(max_drop_percent, min_stops)
    new_n = new["n"]
    if new_n < floor:
        raise DecisionError("stop count %d is below the floor of %d" % (new_n, floor))

    old_n = deployed.get("n") if deployed is not None else None
    if _is_int(old_n) and old_n > 0:
        # Drop strictly greater than the allowed percentage fails (exact maths).
        if (old_n - new_n) * 100 > percent * old_n:
            raise DecisionError(
                "stop count fell from %d to %d, more than the allowed %s%%"
                % (old_n, new_n, max_drop_percent))

    if deployed is None:
        return True, "first-deploy"
    if force:
        return True, "force"
    if deployed.get("gv") != new["gv"]:
        return True, "generator-version-changed"
    if deployed.get("h") != new["h"]:
        return True, "stop-data-changed"
    return False, "unchanged"


def _emit(**pairs):
    for key, value in pairs.items():
        print("%s=%s" % (key, value))


def _run(args):
    if args.command == "classify-deployed":
        status = classify_deployed(args.http_code)
        _emit(present=str(status == "present").lower())
    elif args.command == "plan-fetch":
        conditional, etag, reason = plan_fetch(load_deployed(args.deployed),
                                               parse_bool(args.force))
        print("fetch plan: %s (%s)" % ("conditional" if conditional else "unconditional",
                                       reason), file=sys.stderr)
        _emit(mode="conditional" if conditional else "unconditional",
              if_none_match=etag)
    elif args.command == "classify-fetch":
        result = classify_fetch(args.http_code, parse_bool(args.conditional), args.file)
        _emit(result=result)
    elif args.command == "etag":
        with open(args.header_file, "r", encoding="utf-8", errors="replace") as handle:
            _emit(etag=extract_etag(handle.read()))
    elif args.command == "decide":
        deploy, reason = decide(load_new(args.new), load_deployed(args.deployed),
                                parse_bool(args.force), args.max_drop_percent,
                                args.min_stops)
        print("decision: %s (%s)" % ("deploy" if deploy else "skip deploy", reason),
              file=sys.stderr)
        _emit(deploy=str(deploy).lower(), reason=reason)


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("classify-deployed")
    p.add_argument("--http-code", type=int, required=True)

    p = sub.add_parser("plan-fetch")
    p.add_argument("--deployed", required=True)
    p.add_argument("--force", default="false")

    p = sub.add_parser("classify-fetch")
    p.add_argument("--http-code", type=int, required=True)
    p.add_argument("--conditional", required=True)
    p.add_argument("--file")

    p = sub.add_parser("etag")
    p.add_argument("header_file")

    p = sub.add_parser("decide")
    p.add_argument("--new", required=True)
    p.add_argument("--deployed", required=True)
    p.add_argument("--force", default="false")
    p.add_argument("--max-drop-percent", default=DEFAULT_MAX_DROP_PERCENT)
    p.add_argument("--min-stops", default=DEFAULT_MIN_STOPS)
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        _run(args)
    except DecisionError as error:
        print("error: %s" % error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
