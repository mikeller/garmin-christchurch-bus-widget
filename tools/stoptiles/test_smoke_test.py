"""Unit tests for smoke_test.py (standard library only).

Every failure case of the post-deploy smoke test is exercised against a stub
HTTP server on 127.0.0.1 that serves a real generator output tree.

Run with: python3 -m unittest discover tools/stoptiles
"""

import contextlib
import http.server
import io
import json
import os
import tempfile
import threading
import unittest

import generate_tiles
import smoke_test as st

STOP = 53090
OUTSIDE = "t/0/0.json"

# Synthetic stops around the Bus Interchange; negative latitude exercises the
# floor division in the tile id.
STOPS_TXT = "\n".join(
    ["stop_id,stop_code,stop_name,stop_lat,stop_lon,location_type"]
    + ["%d,%d,Synthetic Stop %d,%.5f,%.5f,0"
       % (code, code, code, -43.53200 - 0.0003 * i, 172.63700 + 0.0004 * i)
       for i, code in enumerate([53090, 53091, 53092, 53093, 53094, 53095, 53096,
                                 53097, 53098, 53099, 53100, 53101, 53102, 53103,
                                 53104, 53105, 53106, 53107])]
    + ["2107,2107,Far Away Stop,-43.60000,172.70000,0"]) + "\n"


class StubSite:
    """A stub Pages site. ``routes`` maps URL path -> (status, body bytes)."""

    def __init__(self, routes):
        self.routes = dict(routes)
        self.requests = []
        site = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                path = self.path.split("?", 1)[0].lstrip("/")
                site.requests.append(self.path)
                status, body = site.routes.get(
                    path, (404, b"<html><body>404 File not found</body></html>"))
                self.send_response(status)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = "http://127.0.0.1:%d" % self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever,
                                       kwargs={"poll_interval": 0.01}, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()


def routes_from_site(site_dir):
    routes = {}
    for directory, _subdirs, files in os.walk(site_dir):
        for name in files:
            full = os.path.join(directory, name)
            rel = os.path.relpath(full, site_dir).replace(os.sep, "/")
            with open(full, "rb") as handle:
                routes[rel] = (200, handle.read())
    return routes


def dumps(obj):
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


class SiteTestCase(unittest.TestCase):
    """Generates one real site tree for all tests in the class."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        stops = os.path.join(cls.tmp.name, "stops.txt")
        with open(stops, "w", encoding="utf-8") as handle:
            handle.write(STOPS_TXT)
        cls.site = os.path.join(cls.tmp.name, "site")
        generate_tiles.generate(stops, cls.site, date="2026-11-12",
                                out=io.StringIO())
        with open(os.path.join(cls.site, "meta.json"), encoding="utf-8") as handle:
            cls.meta = json.load(handle)
        cls.routes = routes_from_site(cls.site)
        cls.tile = st.home_tile(cls.site, STOP)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def good_routes(self):
        return dict(self.routes)

    def check(self, routes, **overrides):
        """Run `check` against a stub site; returns (exit code, stderr)."""
        params = {"h": self.meta["h"], "gv": self.meta["gv"], "tile": self.tile,
                  "outside": OUTSIDE, "max_seconds": 0, "delay": 0}
        params.update(overrides)
        argv = ["check", "--expect-h", params["h"],
                "--expect-gv", str(params["gv"]), "--tile", params["tile"],
                "--stop", str(STOP), "--max-seconds", str(params["max_seconds"]),
                "--delay", str(params["delay"]), "--timeout", "5"]
        if params["outside"]:
            argv += ["--outside-path", params["outside"]]
        err = io.StringIO()
        with StubSite(routes) as stub, contextlib.redirect_stderr(err):
            code = st.main(argv + ["--base-url", stub.url])
        return code, err.getvalue()


class BuildValuesTest(SiteTestCase):
    def test_tile_id_is_computed_from_the_stop_coordinates(self):
        # -43.53200 / 172.63700 -> latE5 -4353200, lonE5 17263700: floor division
        # puts them in tiles -4354 and 17263, not the truncated -4353.
        self.assertEqual(self.tile, "t/-4354/17263.json")
        self.assertIn(self.tile.split("/", 1)[1].replace("/", os.sep),
                      [os.path.relpath(os.path.join(d, f), os.path.join(self.site, "t"))
                       for d, _s, files in os.walk(os.path.join(self.site, "t"))
                       for f in files])

    def test_cli_prints_h_gv_and_tile(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = st.main(["build-values", "--site", self.site, "--stop", str(STOP)])
        self.assertEqual(code, 0)
        self.assertEqual(out.getvalue().splitlines(),
                         ["h=%s" % self.meta["h"], "gv=%d" % self.meta["gv"],
                          "tile=%s" % self.tile])

    def test_missing_stop_is_a_warning_with_an_empty_tile(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = st.main(["build-values", "--site", self.site, "--stop", "99999"])
        self.assertEqual(code, 0)
        self.assertIn("tile=\n", out.getvalue())
        self.assertIn("not in the build output", err.getvalue())

    def test_unreadable_meta_fails(self):
        with tempfile.TemporaryDirectory() as empty:
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                self.assertEqual(st.main(["build-values", "--site", empty]), 1)
            self.assertIn("cannot read", err.getvalue())


class CheckFailureCasesTest(SiteTestCase):
    def test_passes_against_the_real_generator_output(self):
        with StubSite(self.good_routes()) as stub:
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                code = st.main([
                    "check", "--base-url", stub.url, "--expect-h", self.meta["h"],
                    "--expect-gv", str(self.meta["gv"]), "--tile", self.tile,
                    "--stop", str(STOP), "--outside-path", OUTSIDE,
                    "--max-seconds", "0", "--delay", "0"])
            self.assertEqual(code, 0, err.getvalue())
            self.assertEqual(len(stub.requests), 3)
            self.assertTrue(all("?smoke=local-1" in r for r in stub.requests))

    def test_missing_tile_fails(self):
        routes = self.good_routes()
        del routes[self.tile]
        code, err = self.check(routes)
        self.assertEqual(code, 1)
        self.assertIn("HTTP 404, expected 200", err)

    def test_non_json_body_fails(self):
        routes = self.good_routes()
        routes[self.tile] = (200, b"<html><body>Not a tile</body></html>")
        code, err = self.check(routes)
        self.assertEqual(code, 1)
        self.assertIn("not valid JSON", err)

    def test_oversized_tile_fails(self):
        routes = self.good_routes()
        tile = json.loads(routes[self.tile][1])
        tile["s"] += [[60000 + i, -4353200, 17263700, "Padding stop %d" % i]
                      for i in range(200)]
        body = dumps(tile)
        self.assertGreater(len(body), 4096)
        routes[self.tile] = (200, body)
        code, err = self.check(routes)
        self.assertEqual(code, 1)
        self.assertIn("over the 4096 byte limit", err)

    def test_tile_of_exactly_the_limit_passes(self):
        routes = self.good_routes()
        tile = json.loads(routes[self.tile][1])
        body = dumps(tile)
        padding = 4096 - len(body)
        self.assertGreater(padding, 0)
        tile["g"] = tile["g"] + "x" * padding
        body = dumps(tile)
        self.assertEqual(len(body), 4096)
        routes[self.tile] = (200, body)
        self.assertEqual(self.check(routes)[0], 0)

    def test_missing_stop_fails(self):
        routes = self.good_routes()
        tile = json.loads(routes[self.tile][1])
        tile["s"] = [e for e in tile["s"] if e[0] != STOP]
        routes[self.tile] = (200, dumps(tile))
        code, err = self.check(routes)
        self.assertEqual(code, 1)
        self.assertIn("stop 53090 is missing", err)

    def test_stop_code_as_a_string_does_not_count(self):
        routes = self.good_routes()
        routes[self.tile] = (200, dumps({"v": 1, "s": [["53090", 1, 2, "x"]]}))
        self.assertEqual(self.check(routes)[0], 1)

    def test_h_mismatch_fails(self):
        code, err = self.check(self.good_routes(), h="0" * 64)
        self.assertEqual(code, 1)
        self.assertIn("meta.json: h is", err)

    def test_gv_mismatch_fails(self):
        code, err = self.check(self.good_routes(), gv=self.meta["gv"] + 1)
        self.assertEqual(code, 1)
        self.assertIn("meta.json: gv is", err)

    def test_meta_missing_fails(self):
        routes = self.good_routes()
        del routes["meta.json"]
        code, err = self.check(routes)
        self.assertEqual(code, 1)
        self.assertIn("meta.json: HTTP 404", err)

    def test_meta_non_json_and_wrong_version_fail(self):
        routes = self.good_routes()
        routes["meta.json"] = (200, b"<html></html>")
        self.assertIn("not valid JSON", self.check(routes)[1])
        meta = dict(self.meta, v=2)
        routes["meta.json"] = (200, dumps(meta))
        code, err = self.check(routes)
        self.assertEqual(code, 1)
        self.assertIn("meta.json: v is 2", err)

    def test_tile_wrong_version_fails(self):
        routes = self.good_routes()
        tile = json.loads(routes[self.tile][1])
        tile["v"] = 2
        routes[self.tile] = (200, dumps(tile))
        code, err = self.check(routes)
        self.assertEqual(code, 1)
        self.assertIn("v is 2", err)

    def test_boolean_version_is_not_one(self):
        routes = self.good_routes()
        tile = json.loads(routes[self.tile][1])
        tile["v"] = True
        routes[self.tile] = (200, dumps(tile))
        self.assertEqual(self.check(routes)[0], 1)

    def test_invalid_utf8_tile_fails(self):
        routes = self.good_routes()
        routes[self.tile] = (200, b'{"v":1,"s":[[53090,1,2,"Caf\xe9"]]}')
        code, err = self.check(routes)
        self.assertEqual(code, 1)
        self.assertIn("not valid UTF-8", err)

    def test_json_that_is_not_an_object_fails(self):
        routes = self.good_routes()
        routes[self.tile] = (200, b"[1,2,3]")
        code, err = self.check(routes)
        self.assertEqual(code, 1)
        self.assertIn("not a JSON object", err)

    def test_outside_coverage_must_be_404(self):
        routes = self.good_routes()
        routes[OUTSIDE] = (200, b"{}")
        code, err = self.check(routes)
        self.assertEqual(code, 1)
        self.assertIn("expected 404 outside coverage", err)

    def test_outside_check_is_optional(self):
        routes = self.good_routes()
        routes[OUTSIDE] = (200, b"{}")
        self.assertEqual(self.check(routes, outside="")[0], 0)

    def test_unreachable_server_fails(self):
        with StubSite({}) as stub:
            url = stub.url
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code = st.main(["check", "--base-url", url, "--expect-h", self.meta["h"],
                            "--expect-gv", "1", "--tile", self.tile,
                            "--max-seconds", "0", "--delay", "0", "--timeout", "2"])
        self.assertEqual(code, 1)
        self.assertIn("request failed", err.getvalue())

    def test_malformed_arguments_fail_without_requests(self):
        for argv in (["--expect-h", "abc", "--tile", self.tile],
                     ["--expect-h", self.meta["h"], "--tile", ""],
                     ["--expect-h", self.meta["h"], "--tile", "../etc/passwd"],
                     ["--expect-h", self.meta["h"], "--tile", "t/1/2.json?x=y"]):
            with StubSite(self.good_routes()) as stub:
                err = io.StringIO()
                with contextlib.redirect_stderr(err):
                    code = st.main(["check", "--base-url", stub.url, "--expect-gv", "1",
                                    "--max-seconds", "0"] + argv)
                self.assertEqual(code, 1, argv)
                self.assertEqual(stub.requests, [], argv)
                self.assertIn("error:", err.getvalue())


class RetryTest(SiteTestCase):
    def test_retries_until_the_cdn_serves_the_new_site(self):
        """The first requests see the old site (404 tile, old h); then it flips."""
        good = self.good_routes()
        stale = dict(good)
        del stale[self.tile]
        stale["meta.json"] = (200, dumps(dict(self.meta, h="1" * 64)))
        with StubSite(stale) as stub:
            calls = []

            def sleep(seconds):
                calls.append(seconds)
                if len(calls) == 2:
                    stub.routes.update(good)  # propagation completes

            err = io.StringIO()
            ok = st.run_check(
                lambda url: st.http_fetch(url, 5), stub.url, self.meta["h"],
                self.meta["gv"], self.tile, STOP, OUTSIDE, max_seconds=300,
                delay=30, token="t", sleep=sleep, clock=lambda: 0, out=err)
        self.assertTrue(ok, err.getvalue())
        self.assertEqual(calls, [30, 30])
        self.assertIn("passed on attempt 3", err.getvalue())
        # Each attempt uses its own cache-busting query string.
        self.assertEqual(sorted({r.split("?smoke=")[1] for r in stub.requests}),
                         ["t-1", "t-2", "t-3"])

    def test_gives_up_when_the_time_budget_is_spent(self):
        now = [0.0]

        def sleep(seconds):
            now[0] += seconds

        routes = self.good_routes()
        del routes[self.tile]
        with StubSite(routes) as stub:
            err = io.StringIO()
            ok = st.run_check(
                lambda url: st.http_fetch(url, 5), stub.url, self.meta["h"],
                self.meta["gv"], self.tile, STOP, None, max_seconds=100,
                delay=30, sleep=sleep, clock=lambda: now[0], out=err)
        self.assertFalse(ok)
        # Attempts at t = 0, 30, 60, 90; a fifth at 120 would exceed the budget.
        self.assertEqual(err.getvalue().count("HTTP 404, expected 200"), 4)
        self.assertIn("failed after 4 attempt(s)", err.getvalue())


if __name__ == "__main__":
    unittest.main()
