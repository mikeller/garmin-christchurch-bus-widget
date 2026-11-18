"""Unit tests for service_metadata_canary.py (standard library only).

Run with: python3 -m unittest discover tools/stoptiles
"""

import contextlib
import io
import tempfile
import unittest
import zipfile
from pathlib import Path

import service_metadata_canary as canary
from generate_tiles import MAX_TILE_BYTES

DATE = "2026-11-18"


def fixture(path, changes=None):
    """A minimal GTFS zip that satisfies the service-metadata preconditions."""
    data = {
        "stops": ("stop_id,stop_code,stop_lat,stop_lon,stop_name\n"
                  "internal,1001,-43.5,172.6,Rapaki\n"
                  "other,1002,-43.5,172.601,Other\n"),
        "routes": "route_id,route_short_name\nZ,10\n",
        "trips": ("trip_id,route_id,direction_id,service_id\n"
                  "t1,Z,1,weekday\n"),
        "stop_times": "stop_id,trip_id,pickup_type\ninternal,t1,0\nother,t1,0\n",
        "calendar": ("service_id,monday,tuesday,wednesday,thursday,friday,"
                     "saturday,sunday,start_date,end_date\n"
                     "weekday,1,1,1,1,1,0,0,20261101,20261130\n"),
        "calendar_dates": "service_id,date,exception_type\n",
        "feed_info": "feed_start_date,feed_end_date\n20261101,20261130\n",
    }
    for name, text in (changes or {}).items():
        if text is None:
            data.pop(name, None)
        else:
            data[name] = text
    with zipfile.ZipFile(path, "w") as archive:
        for name, text in data.items():
            archive.writestr(name + ".txt", text)


class CheckPassTests(unittest.TestCase):
    def test_pass_reports_tiles_k_size_and_headroom(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fixture(base / "gtfs.zip")
            scratch = base / "scratch"
            result = canary.check(str(base / "gtfs.zip"), str(scratch), date=DATE)
            self.assertGreater(result["tiles"], 0)
            self.assertEqual(result["k"], 1)
            self.assertGreater(result["max_tile_bytes"], 0)
            self.assertLessEqual(result["max_tile_bytes"], MAX_TILE_BYTES)
            self.assertEqual(result["headroom"],
                             MAX_TILE_BYTES - result["max_tile_bytes"])
            # The generator actually ran: the scratch tree has real tiles.
            self.assertTrue((scratch / "meta.json").exists())
            self.assertTrue(list((scratch / "t").rglob("*.json")))

    def test_report_prints_pass_verdict_and_metrics(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fixture(base / "gtfs.zip")
            out = io.StringIO()
            canary.report(str(base / "gtfs.zip"), str(base / "scratch"),
                          date=DATE, out=out)
            lines = out.getvalue().splitlines()
            self.assertEqual(lines[-1], "PRECONDITIONS: PASS")
            joined = "\n".join(lines)
            self.assertRegex(joined, r"tiles: [1-9]\d*")
            self.assertIn("K: 1", joined)
            self.assertRegex(joined, r"max tile bytes: \d+")
            self.assertRegex(joined, r"headroom bytes: \d+")

    def test_scratch_directory_does_not_collide_with_site_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fixture(base / "gtfs.zip")
            site = base / "site"
            scratch = base / "scratch" / "service-metadata-canary"
            site.mkdir()
            (site / "meta.json").write_text('{"marker": "real-site-output"}',
                                            encoding="utf-8")
            (site / "sentinel.txt").write_text("do not touch", encoding="utf-8")
            canary.check(str(base / "gtfs.zip"), str(scratch), date=DATE)
            # The real site tree, with its distinct directory structure, is
            # untouched: the canary never writes outside its scratch directory.
            self.assertEqual((site / "meta.json").read_text(encoding="utf-8"),
                             '{"marker": "real-site-output"}')
            self.assertTrue((site / "sentinel.txt").exists())
            self.assertNotEqual(site.resolve(), scratch.resolve())
            self.assertTrue((scratch / "meta.json").exists())
            self.assertNotIn("sentinel.txt",
                            [p.name for p in scratch.iterdir()])


class CheckFailTests(unittest.TestCase):
    def test_missing_feed_info_fails_with_generator_error_message(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fixture(base / "bad.zip", {"feed_info": None})
            with self.assertRaisesRegex(canary.GeneratorError, "feed_info"):
                canary.check(str(base / "bad.zip"), str(base / "scratch"), date=DATE)

    def test_zero_usable_global_keys_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fixture(base / "none.zip", {
                "stop_times": "stop_id,trip_id,pickup_type\ninternal,t1,2\nother,t1,3\n"})
            with self.assertRaisesRegex(canary.GeneratorError, "1..1296"):
                canary.check(str(base / "none.zip"), str(base / "scratch"), date=DATE)

    def test_report_prints_fail_verdict_and_exits_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fixture(base / "none.zip", {
                "stop_times": "stop_id,trip_id,pickup_type\ninternal,t1,2\nother,t1,3\n"})
            out = io.StringIO()
            # report() never raises: this call itself is the exit-0 proof.
            canary.report(str(base / "none.zip"), str(base / "scratch"), date=DATE,
                         out=out)
            lines = out.getvalue().splitlines()
            self.assertEqual(lines[-1], "PRECONDITIONS: FAIL")
            self.assertTrue(any("1..1296" in line for line in lines[:-1]))

            # main() wraps the same call and always returns 0.
            scratch = base / "cli-scratch"
            gtfs = base / "none.zip"
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                returncode = canary.main([str(gtfs), str(scratch)])
            self.assertEqual(returncode, 0)
            self.assertIn("PRECONDITIONS: FAIL", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
