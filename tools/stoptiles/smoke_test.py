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

check --base-url URL --expect-h H --expect-gv N --tile PATH --stop CODE
      [--outside-path PATH] [--max-seconds S] [--delay S] [--timeout S]
      [--cache-bust TOKEN]
    Fetch the published ``meta.json`` and the tile at PATH and assert:

    * ``meta.json``: HTTP 200, valid UTF-8 JSON object, ``v == 1``, ``h`` and
      ``gv`` equal the build's values;
    * the tile: HTTP 200, valid UTF-8 JSON object, ``v == 1``, at most
      MAX_TILE_BYTES (4096) bytes, and ``s`` contains stop CODE;
    * optionally, OUTSIDE-PATH (a tile far outside coverage) returns HTTP 404.
      That is why the watch sees responseCode -400 outside coverage: Pages
      answers with a 404 HTML page, which is not JSON.

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

META_PATH = "meta.json"
DEFAULT_STOP = 53090
DEFAULT_MAX_SECONDS = 480
DEFAULT_DELAY = 30
DEFAULT_TIMEOUT = 15
READ_LIMIT = 65536  # never read more than this from a response

_TILE_PATH_RE = re.compile(r"t/-?[0-9]+/-?[0-9]+\.json", re.ASCII)
_SHA256_RE = re.compile(r"[0-9a-f]{64}", re.ASCII)


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


def check_meta(status, body, expect_h, expect_gv):
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
    if meta.get("h") != expect_h:
        failures.append("meta.json: h is %r, expected %r (the build's value)"
                        % (meta.get("h"), expect_h))
    if not (_is_int(meta.get("gv")) and meta["gv"] == expect_gv):
        failures.append("meta.json: gv is %r, expected %d (the build's value)"
                        % (meta.get("gv"), expect_gv))
    return failures


def check_tile(status, body, stop_code, tile_path="tile"):
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
               outside_path, token):
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
        failures += check_meta(result[0], result[1], expect_h, expect_gv)
    result = get(tile_path)
    if result is not None:
        failures += check_tile(result[0], result[1], stop_code, tile_path)
    if outside_path:
        result = get(outside_path)
        if result is not None:
            failures += check_outside(result[0], outside_path)
    return failures


def validate_arguments(expect_h, expect_gv, tile_path, outside_path):
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


def run_check(fetch, base_url, expect_h, expect_gv, tile_path, stop_code,
              outside_path=None, max_seconds=DEFAULT_MAX_SECONDS,
              delay=DEFAULT_DELAY, token="local", sleep=time.sleep,
              clock=time.monotonic, out=None):
    """Retry check_once until it passes or max_seconds elapse. Returns bool."""
    out = out or sys.stderr
    validate_arguments(expect_h, expect_gv, tile_path, outside_path)
    start = clock()
    attempt = 0
    while True:
        attempt += 1
        failures = check_once(fetch, base_url, expect_h, expect_gv, tile_path,
                              stop_code, outside_path, "%s-%d" % (token, attempt))
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
        return 0
    ok = run_check(
        lambda url: http_fetch(url, args.timeout), args.base_url, args.expect_h,
        args.expect_gv, args.tile, args.stop, args.outside_path or None,
        args.max_seconds, args.delay, args.cache_bust)
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
