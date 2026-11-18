#!/usr/bin/env python3
"""Smoke test for the published stop tiles (standard library only).

The workflow calls these subcommands so that every assertion can be exercised
locally against a stub HTTP server. Machine-readable results are ``key=value``
lines on stdout; human-readable messages go to stderr. The script never reads
or needs the Metro API key and only issues GET requests to the given base URL.

Subcommands
-----------
build-values --site DIR --stop CODE
    Read the freshly generated site and print ``h=<sha256>``, ``gv=<int>`` (from
    ``meta.json``) and ``tile=t/<ty>/<tx>.json``: the tile that contains stop
    CODE itself, with the tile id computed from the stop's own coordinates by
    the generator's ``tile_id`` (never hard-coded). When the build output has no
    such stop, ``tile=`` is empty and a warning is printed; this is not an
    error here, so a renumbered reference stop never blocks a deploy of valid
    data. The post-deploy ``check`` then fails with a clear message.

    When ``meta.json`` has ``m == 2`` (the opt-in service-metadata v2 fields,
    see generate_tiles.py), also prints ``k=<int>`` (the global key count
    ``K``) and ``sh=<sha256>`` (the service digest ``sh``), after validating
    that they are well-formed. When ``m`` is not 2, no ``k``/``sh`` lines are
    printed at all, so the workflow's outputs stay empty and the smoke test
    below correctly expects the v2 fields to be absent.

check --base-url URL --expect-h H --expect-gv N --tile PATH --stop CODE
      [--outside-path PATH] [--max-seconds S] [--delay S] [--timeout S]
      [--cache-bust TOKEN] [--expect-k K --expect-sh SH]
    Fetch the published ``meta.json`` and the tile at PATH and assert:

    * ``meta.json``: HTTP 200, valid UTF-8 JSON object, ``v == 1``, ``h`` and
      ``gv`` equal the build's values;
    * the tile: HTTP 200, valid UTF-8 JSON object, ``v == 1``, at most
      MAX_TILE_BYTES (4096) bytes, and ``s`` contains stop CODE;
    * optionally, OUTSIDE-PATH (a tile far outside coverage) returns HTTP 404.
      That is why the watch sees responseCode -400 outside coverage: Pages
      answers with a 404 HTML page, which is not JSON.

    ``--expect-k``/``--expect-sh`` are optional and must be given together.
    They encode whether the build ran with the service-metadata v2 opt-in:

    * when given, additionally assert ``meta.json["m"] == 2``,
      ``meta.json["K"] == K``, ``meta.json["sh"] == SH`` and
      ``meta.json["h"] == meta.json["sh"]``; and that the tile has
      ``m == 2``, ``K == K``, ``sh == SH``, ``len(i) == len(s)``, every entry
      of ``i`` is either ``null`` or a non-empty even-length lower-case
      base36 string whose decoded two-character groups are each less than K
      and strictly increasing, and ``p`` is a list of stop codes that is a
      subset of the codes in ``s``. Checking the tile's own K/sh, not just
      meta.json's, is what catches a CDN serving a stale tile from an
      earlier build alongside current metadata;
    * when omitted (the default, matching PR #19's claim that disabled-mode
      output is byte-identical to v1), assert instead that none of the v2
      keys (``m``, ``sh``, ``K``, ``i``, ``p``) are present at all in either
      ``meta.json`` or the tile.

    Every attempt re-checks everything. A failing attempt is retried every
    DELAY seconds (CDN propagation after a deploy) until MAX-SECONDS have
    elapsed; the exit status is non-zero when the last attempt still fails.
    Each request carries a cache-busting query string.
"""

import argparse
import http.client
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

from generate_tiles import MAX_TILE_BYTES, TILE_FORMAT_VERSION, tile_id
from service_metadata import ALPHABET

META_PATH = "meta.json"
DEFAULT_STOP = 53090
DEFAULT_MAX_SECONDS = 480
DEFAULT_DELAY = 30
DEFAULT_TIMEOUT = 15
READ_LIMIT = 65536  # never read more than this from a response
V2_FIELDS = ("m", "sh", "K", "i", "p")
MAX_GLOBAL_KEYS = 1296  # service_metadata.build: 1..1296 usable global keys

_TILE_PATH_RE = re.compile(r"t/-?[0-9]+/-?[0-9]+\.json", re.ASCII)
_SHA256_RE = re.compile(r"[0-9a-f]{64}", re.ASCII)
_BASE36_VALUES = {char: value for value, char in enumerate(ALPHABET)}


class SmokeError(Exception):
    """A condition that must fail the step with a clear message."""


class FetchError(Exception):
    """A transport-level failure (DNS, connection, TLS, timeout)."""


def _is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def _parse_json_object(body):
    """Return (obj, None) for a UTF-8 JSON object body, else (None, reason)."""
    try:
        text = body.decode("utf-8")
    except UnicodeDecodeError as error:
        return None, "body is not valid UTF-8 (%s)" % error
    try:
        obj = json.loads(text)
    except ValueError as error:
        return None, "body is not valid JSON (%s)" % error
    if not isinstance(obj, dict):
        return None, "body is not a JSON object"
    return obj, None


def _check_v2_absent(obj, label):
    """Failures if any v1/v2 wire field (m, sh, K, i, p) is present at all.

    Guards PR #19's claim that default-mode (v2 disabled) output is
    byte-identical to v1: none of the opt-in fields may leak in even when the
    service-metadata opt-in is off.
    """
    present = [field for field in V2_FIELDS if field in obj]
    if present:
        return ["%s: unexpected v2 field(s) present: %s"
                % (label, ", ".join(present))]
    return []


def _decode_index_entry(value, expect_k, label):
    """Failures for one entry of a v2 tile's ``i`` array."""
    if value is None:
        return []
    if (not isinstance(value, str) or not value or len(value) % 2 != 0
            or any(char not in _BASE36_VALUES for char in value)):
        return ["%s: i entry %r is not null or a non-empty even-length "
                "lower-case base36 string" % (label, value)]
    indices = [_BASE36_VALUES[value[pos]] * 36 + _BASE36_VALUES[value[pos + 1]]
              for pos in range(0, len(value), 2)]
    failures = []
    if any(index >= expect_k for index in indices):
        failures.append("%s: i entry %r has a decoded index >= K (%d)"
                        % (label, value, expect_k))
    if any(a >= b for a, b in zip(indices, indices[1:])):
        failures.append("%s: i entry %r is not strictly increasing"
                        % (label, value))
    return failures


def _check_tile_v2(tile, expect_k, expect_sh, label):
    """Failures for a v2 tile's m, K, sh, i and p fields.

    The tile embeds its own K and sh (service_metadata.encode, merged into
    every tile by encode_tile), identical to the build's meta.json values.
    Checking them here, not just on meta.json, is what lets this catch a CDN
    serving a stale tile from an earlier build alongside current metadata:
    without this, a stale tile could still pass if its i indices happened to
    stay below the new K.
    """
    failures = []
    if not (_is_int(tile.get("m")) and tile["m"] == 2):
        failures.append("%s: m is %r, expected 2" % (label, tile.get("m")))
    if not (_is_int(tile.get("K")) and tile["K"] == expect_k):
        failures.append("%s: K is %r, expected %d (the build's value)"
                        % (label, tile.get("K"), expect_k))
    if tile.get("sh") != expect_sh:
        failures.append("%s: sh is %r, expected %r (the build's value)"
                        % (label, tile.get("sh"), expect_sh))
    stops = tile.get("s")
    stop_count = len(stops) if isinstance(stops, list) else None
    indices = tile.get("i")
    if not isinstance(indices, list):
        failures.append("%s: i is not a list" % label)
    else:
        if stop_count is not None and len(indices) != stop_count:
            failures.append("%s: i has %d entries, expected %d (len(s))"
                            % (label, len(indices), stop_count))
        for entry in indices:
            failures += _decode_index_entry(entry, expect_k, label)
    partial = tile.get("p")
    if not isinstance(partial, list):
        failures.append("%s: p is not a list" % label)
    elif isinstance(stops, list):
        codes = {entry[0] for entry in stops
                if isinstance(entry, list) and entry and _is_int(entry[0])}
        if not all(_is_int(code) and code in codes for code in partial):
            failures.append("%s: p (%r) is not a subset of the stop codes in s"
                            % (label, partial))
    return failures


def check_meta(status, body, expect_h, expect_gv, expect_k=None, expect_sh=None):
    """Failures (a list of messages) for the published meta.json."""
    if status != 200:
        return ["meta.json: HTTP %s, expected 200" % status]
    meta, reason = _parse_json_object(body)
    if reason:
        return ["meta.json: %s" % reason]
    failures = []
    if not (_is_int(meta.get("v")) and meta["v"] == TILE_FORMAT_VERSION):
        failures.append("meta.json: v is %r, expected %d"
                        % (meta.get("v"), TILE_FORMAT_VERSION))
    if not (_is_int(meta.get("gv")) and meta["gv"] == expect_gv):
        failures.append("meta.json: gv is %r, expected %d (the build's value)"
                        % (meta.get("gv"), expect_gv))
    if meta.get("h") != expect_h:
        failures.append("meta.json: h is %r, expected %r (the build's value)"
                        % (meta.get("h"), expect_h))
    if expect_k is None:
        failures += _check_v2_absent(meta, "meta.json")
        return failures
    if not (_is_int(meta.get("m")) and meta["m"] == 2):
        failures.append("meta.json: m is %r, expected 2" % meta.get("m"))
    if not (_is_int(meta.get("K")) and meta["K"] == expect_k):
        failures.append("meta.json: K is %r, expected %d (the build's value)"
                        % (meta.get("K"), expect_k))
    if meta.get("sh") != expect_sh:
        failures.append("meta.json: sh is %r, expected %r (the build's value)"
                        % (meta.get("sh"), expect_sh))
    if meta.get("h") != meta.get("sh"):
        failures.append("meta.json: h (%r) does not equal sh (%r)"
                        % (meta.get("h"), meta.get("sh")))
    return failures


def check_tile(status, body, stop_code, tile_path="tile", expect_k=None,
               expect_sh=None):
    """Failures for the published tile that must contain the reference stop."""
    label = "tile %s" % tile_path
    if status != 200:
        return ["%s: HTTP %s, expected 200" % (label, status)]
    failures = []
    if len(body) > MAX_TILE_BYTES:
        failures.append("%s: %d bytes, over the %d byte limit"
                        % (label, len(body), MAX_TILE_BYTES))
    tile, reason = _parse_json_object(body)
    if reason:
        failures.append("%s: %s" % (label, reason))
        return failures
    if not (_is_int(tile.get("v")) and tile["v"] == TILE_FORMAT_VERSION):
        failures.append("%s: v is %r, expected %d"
                        % (label, tile.get("v"), TILE_FORMAT_VERSION))
    stops = tile.get("s")
    if not isinstance(stops, list):
        failures.append("%s: s is not a list" % label)
    elif not any(isinstance(entry, list) and entry and _is_int(entry[0])
                 and entry[0] == stop_code for entry in stops):
        failures.append("%s: stop %d is missing from s" % (label, stop_code))
    if expect_k is None:
        failures += _check_v2_absent(tile, label)
    else:
        failures += _check_tile_v2(tile, expect_k, expect_sh, label)
    return failures


def check_outside(status, path):
    """The tile far outside coverage must be a plain 404."""
    if status != 404:
        return ["%s: HTTP %s, expected 404 outside coverage" % (path, status)]
    return []


def http_fetch(url, timeout):
    """GET url. Returns (status, body); HTTP errors are statuses, not raises."""
    request = urllib.request.Request(url, headers={
        "Cache-Control": "no-cache",
        "User-Agent": "stop-tiles-smoke-test",
    })
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read(READ_LIMIT)
    except urllib.error.HTTPError as error:
        # An exception raised here is not caught by the sibling clause below, so
        # a stalled or truncated error body must be converted explicitly.
        try:
            return error.code, error.read(READ_LIMIT)
        except (http.client.HTTPException, OSError) as read_error:
            raise FetchError("%s: reading the HTTP %d response body failed: %s"
                             % (url.split("?", 1)[0], error.code, read_error))
        finally:
            error.close()
    except (urllib.error.URLError, http.client.HTTPException, OSError) as error:
        raise FetchError("%s: %s" % (url.split("?", 1)[0], error))


def _url(base_url, path, token):
    return "%s/%s?smoke=%s" % (base_url.rstrip("/"), path, token)


def check_once(fetch, base_url, expect_h, expect_gv, tile_path, stop_code,
               outside_path, token, expect_k=None, expect_sh=None):
    """One pass over every assertion. Returns the list of failure messages."""
    failures = []

    def get(path):
        try:
            return fetch(_url(base_url, path, token))
        except FetchError as error:
            failures.append("%s: request failed (%s)" % (path, error))
            return None

    result = get(META_PATH)
    if result is not None:
        failures += check_meta(result[0], result[1], expect_h, expect_gv,
                               expect_k, expect_sh)
    result = get(tile_path)
    if result is not None:
        failures += check_tile(result[0], result[1], stop_code, tile_path,
                               expect_k, expect_sh)
    if outside_path:
        result = get(outside_path)
        if result is not None:
            failures += check_outside(result[0], outside_path)
    return failures


def validate_arguments(expect_h, expect_gv, tile_path, outside_path,
                       expect_k=None, expect_sh=None):
    if not _SHA256_RE.fullmatch(expect_h or ""):
        raise SmokeError("--expect-h is not a sha256 hex digest: %r" % expect_h)
    if not tile_path:
        raise SmokeError("the build output has no tile for the reference stop, "
                         "so the stop cannot be smoke tested (was it renumbered "
                         "or removed from the feed?)")
    for path in (tile_path, outside_path):
        if path and not _TILE_PATH_RE.fullmatch(path):
            raise SmokeError("not a tile path (t/<ty>/<tx>.json): %r" % path)
    if not _is_int(expect_gv):
        raise SmokeError("--expect-gv is not an integer")
    if (expect_k is None) != (expect_sh is None):
        raise SmokeError("--expect-k and --expect-sh must be given together")
    if expect_k is not None and not (_is_int(expect_k) and 1 <= expect_k <= MAX_GLOBAL_KEYS):
        raise SmokeError("--expect-k is not an integer in 1..%d: %r"
                         % (MAX_GLOBAL_KEYS, expect_k))
    if expect_sh is not None and not _SHA256_RE.fullmatch(expect_sh or ""):
        raise SmokeError("--expect-sh is not a sha256 hex digest: %r" % expect_sh)


def run_check(fetch, base_url, expect_h, expect_gv, tile_path, stop_code,
              outside_path=None, max_seconds=DEFAULT_MAX_SECONDS,
              delay=DEFAULT_DELAY, token="local", sleep=time.sleep,
              clock=time.monotonic, out=None, expect_k=None, expect_sh=None):
    """Retry check_once until it passes or max_seconds elapse. Returns bool."""
    out = out or sys.stderr
    validate_arguments(expect_h, expect_gv, tile_path, outside_path,
                       expect_k, expect_sh)
    start = clock()
    attempt = 0
    while True:
        attempt += 1
        failures = check_once(fetch, base_url, expect_h, expect_gv, tile_path,
                              stop_code, outside_path, "%s-%d" % (token, attempt),
                              expect_k, expect_sh)
        if not failures:
            print("smoke test passed on attempt %d" % attempt, file=out)
            return True
        for failure in failures:
            print("attempt %d: %s" % (attempt, failure), file=out)
        if clock() - start + delay >= max_seconds:
            print("smoke test failed after %d attempt(s)" % attempt, file=out)
            return False
        print("retrying in %s s (the CDN may still be propagating)" % delay,
              file=out)
        sleep(delay)


def _load_site_meta(site):
    path = os.path.join(site, META_PATH)
    try:
        with open(path, "r", encoding="utf-8") as handle:
            meta = json.load(handle)
    except (OSError, ValueError) as error:
        raise SmokeError("cannot read %s: %s" % (path, error))
    if (not isinstance(meta, dict) or not isinstance(meta.get("h"), str)
            or not _SHA256_RE.fullmatch(meta["h"]) or not _is_int(meta.get("gv"))):
        raise SmokeError("%s lacks a sha256 h or an integer gv" % path)
    return meta


def _tile_files(site):
    root = os.path.join(site, "t")
    for directory, subdirs, files in os.walk(root):
        subdirs.sort()
        for name in sorted(files):
            if name.endswith(".json"):
                yield os.path.join(directory, name)


def find_stop(site, stop_code):
    """(latE5, lonE5) of the stop from the first tile that lists it, or None."""
    for path in _tile_files(site):
        with open(path, "rb") as handle:
            tile, _reason = _parse_json_object(handle.read())
        for entry in (tile or {}).get("s", []):
            if (isinstance(entry, list) and len(entry) >= 3 and entry[0] == stop_code
                    and _is_int(entry[1]) and _is_int(entry[2])):
                return entry[1], entry[2]
    return None


def home_tile(site, stop_code):
    """Path of the tile that contains the stop's own coordinates, or ''."""
    found = find_stop(site, stop_code)
    if found is None:
        return ""
    path = "t/%d/%d.json" % (tile_id(found[0]), tile_id(found[1]))
    if not os.path.isfile(os.path.join(site, path)):
        raise SmokeError("computed tile %s for stop %d does not exist in %s"
                         % (path, stop_code, site))
    return path


def _run(args):
    if args.command == "build-values":
        meta = _load_site_meta(args.site)
        tile = home_tile(args.site, args.stop)
        if not tile:
            print("warning: stop %d is not in the build output; the smoke test "
                  "will fail" % args.stop, file=sys.stderr)
        print("h=%s" % meta["h"])
        print("gv=%d" % meta["gv"])
        print("tile=%s" % tile)
        if _is_int(meta.get("m")) and meta["m"] == 2:
            k, sh = meta.get("K"), meta.get("sh")
            if not (_is_int(k) and 1 <= k <= MAX_GLOBAL_KEYS):
                raise SmokeError("meta.json has m=2 but K is not an integer "
                                 "in 1..%d: %r" % (MAX_GLOBAL_KEYS, k))
            if not (isinstance(sh, str) and _SHA256_RE.fullmatch(sh)):
                raise SmokeError("meta.json has m=2 but sh is not a sha256 "
                                 "hex digest: %r" % sh)
            print("k=%d" % k)
            print("sh=%s" % sh)
        return 0
    ok = run_check(
        lambda url: http_fetch(url, args.timeout), args.base_url, args.expect_h,
        args.expect_gv, args.tile, args.stop, args.outside_path or None,
        args.max_seconds, args.delay, args.cache_bust,
        expect_k=args.expect_k, expect_sh=args.expect_sh)
    return 0 if ok else 1


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("build-values")
    p.add_argument("--site", required=True)
    p.add_argument("--stop", type=int, default=DEFAULT_STOP)

    p = sub.add_parser("check")
    p.add_argument("--base-url", required=True)
    p.add_argument("--expect-h", required=True)
    p.add_argument("--expect-gv", type=int, required=True)
    p.add_argument("--tile", required=True)
    p.add_argument("--stop", type=int, default=DEFAULT_STOP)
    p.add_argument("--outside-path", default="")
    p.add_argument("--max-seconds", type=float, default=DEFAULT_MAX_SECONDS)
    p.add_argument("--delay", type=float, default=DEFAULT_DELAY)
    p.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    p.add_argument("--cache-bust", default="local")
    p.add_argument("--expect-k", type=int, default=None,
                   help="the build's global key count K; requires --expect-sh")
    p.add_argument("--expect-sh", default=None,
                   help="the build's service digest sh; requires --expect-k")
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        return _run(args)
    except SmokeError as error:
        print("error: %s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
