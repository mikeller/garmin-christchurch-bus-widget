"""Synthetic opt-in producer and shared global wire-contract tests."""
import hashlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

import generate_tiles as gt
import service_metadata as svc

HERE = Path(__file__).resolve().parent
VECTORS = json.loads((HERE / "service_key_vectors.json").read_text(encoding="utf-8"))
DATE = "2026-11-18"


def fixture(path, changes=None, reverse=False):
    data = {
        "stops": ("stop_id,stop_code,stop_lat,stop_lon,stop_name\n"
                  "internal,1001,-43.5,172.6,Rāpaki\n"
                  "other,1002,-43.5,172.601,Other\n"
                  "third,1003,-43.5,172.602,Unknown\n"),
        "routes": "route_id,route_short_name\nZ,10\nA,10\n",
        "trips": ("trip_id,route_id,direction_id,service_id,trip_headsign\n"
                  "t1,Z,1,weekday,East\n"
                  "t2,A,0,exception,West\n"
                  "t3,Z,0,weekday,Other\n"),
        "stop_times": ("stop_id,trip_id,pickup_type,stop_headsign\n"
                       "internal,t1,0,\ninternal,t1,0,Another\n"
                       "internal,t2,0,\nother,t1,0,\nother,missing,0,\n"
                       "other,t3,1,\nthird,t3,1,\n"),
        "calendar": ("service_id,monday,tuesday,wednesday,thursday,friday,"
                     "saturday,sunday,start_date,end_date\n"
                     "weekday,1,1,1,1,1,0,0,20261101,20261130\n"),
        "calendar_dates": ("service_id,date,exception_type\n"
                           "exception,20261118,1\n"),
        "feed_info": ("feed_start_date,feed_end_date\n20261101,20261130\n"),
    }
    data.update(changes or {})
    with zipfile.ZipFile(path, "w") as archive:
        for name, text in data.items():
            lines = text.splitlines()
            if reverse:
                lines = lines[:1] + lines[:0:-1]
            archive.writestr(name + ".txt", "\n".join(lines) + "\n")


def run(path, out, date=DATE):
    return gt.generate(str(path), str(out), date=date, out=io.StringIO(),
                       service_metadata_enabled=True)


def tile(out):
    return json.loads((out / "t" / "-4350" / "17260.json").read_bytes())


def decode(root):
    result = {}
    for stop, value in zip(root["s"], root["i"]):
        if value is not None:
            result[stop[0]] = [
                svc.ALPHABET.index(value[n]) * 36 + svc.ALPHABET.index(value[n + 1])
                for n in range(0, len(value), 2)]
    return result


class ServiceProducerTests(unittest.TestCase):
    def test_global_vectors_and_legacy_rejection(self):
        for case in VECTORS["global_cases"]:
            with self.subTest(case["name"]):
                root = case["tile"]
                self.assertEqual(root["m"], 2)
                self.assertEqual(len(root["s"]), len(root["i"]))
                if case["expected"] is not None:
                    self.assertEqual(decode(root), {
                        int(k): v[1] for k, v in case["expected"].items()})
                    self.assertEqual(root["p"], [int(k) for k, v in
                                                 case["expected"].items() if v[0] == "partial"])
                    for values in decode(root).values():
                        self.assertTrue(values)
                        self.assertEqual(values, sorted(set(values)))
                        self.assertTrue(all(0 <= n < root["K"] for n in values))
                elif case["name"] == "index_out_of_bounds":
                    self.assertGreaterEqual(decode(root)[1001][0], root["K"])
                elif case["name"] == "duplicate_index":
                    self.assertNotEqual(decode(root)[1001],
                                        sorted(set(decode(root)[1001])))
                elif case["name"] == "partial_unknown":
                    self.assertIsNone(root["i"][0])
                    self.assertEqual(root["p"], [1001])
                elif case["name"] == "malformed_odd_length":
                    self.assertEqual(len(root["i"][0]) % 2, 1)
        self.assertEqual(VECTORS["legacy_m1"]["m"], 1)

    def test_join_roundtrip_partial_unknown_unicode_and_row_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fixture(base / "a.zip")
            fixture(base / "b.zip", reverse=True)
            first = run(base / "a.zip", base / "a")
            second = run(base / "b.zip", base / "b")
            self.assertEqual(first, second)
            self.assertEqual(sorted(p.read_bytes() for p in (base / "a" / "t").rglob("*.json")),
                             sorted(p.read_bytes() for p in (base / "b" / "t").rglob("*.json")))
            root = tile(base / "a")
            self.assertEqual(root["v"], 1)
            self.assertEqual(root["m"], 2)
            self.assertEqual(root["K"], 2)
            self.assertEqual(root["p"], [1002])
            self.assertEqual(decode(root), {1001: [0, 1], 1002: [1]})
            self.assertEqual(root["i"], ["0001", "01", None])
            self.assertEqual(len(root["s"][0]), 4)
            self.assertIn("Rāpaki".encode("utf-8"),
                          (base / "a" / "t" / "-4350" / "17260.json").read_bytes())
            self.assertEqual(first["h"], first["sh"])
            self.assertEqual(first["K"], root["K"])
            self.assertEqual(first["sh"], root["sh"])
            self.assertEqual(first["gv"], 2)
            stops, _ = gt.load_stops(str(base / "a.zip"))
            states, keys, digest = svc.build(str(base / "a.zip"), stops, DATE,
                                             gt.stops_hash(stops))
            expected = [2, DATE, gt.stops_hash(stops), "2026-11-01",
                        "2026-11-30", [["A", 0], ["Z", 1]],
                        [[1001, "complete", [["A", 0], ["Z", 1]]],
                         [1002, "partial", [["Z", 1]]],
                         [1003, "unknown", []]]]
            self.assertEqual(digest, hashlib.sha256(gt._dumps(expected).encode()).hexdigest())
            self.assertEqual(keys, [("A", 0), ("Z", 1)])
            self.assertEqual(states[1003], ("unknown", set()))

    def test_digest_changes_for_service_numbering_calendar_reliability_generation(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fixture(base / "a.zip")
            original = run(base / "a.zip", base / "a")
            changes = (
                {"stop_times": "stop_id,trip_id,pickup_type\ninternal,t1,0\nother,t1,0\n"},
                {"routes": "route_id,route_short_name\nZ,10\nB,10\nA,10\n",
                 "trips": ("trip_id,route_id,direction_id,service_id\n"
                           "t1,Z,1,weekday\nt2,B,0,exception\n"
                           "t3,Z,0,weekday\n")},
                {"calendar_dates": "service_id,date,exception_type\nexception,20261118,2\n"},
                {"stop_times": ("stop_id,trip_id,pickup_type\ninternal,t1,0\n"
                                "internal,t2,0\nother,t1,0\n")},
            )
            for n, change in enumerate(changes):
                with self.subTest(n=n):
                    fixture(base / "changed.zip", change)
                    result = run(base / "changed.zip", base / ("out" + str(n)))
                    self.assertNotEqual(result["h"], original["h"])
            self.assertNotEqual(run(base / "a.zip", base / "later", "2026-11-19")["h"],
                                original["h"])
            self.assertEqual(gt.load_stops(str(base / "a.zip"))[0],
                             gt.load_stops(str(base / "changed.zip"))[0])

    def test_invalid_references_horizon_and_missing_tables_fail_before_output(self):
        cases = (
            {"trips": "trip_id,route_id,direction_id,service_id\nt1,Z,1,missing\n"},
            {"trips": "trip_id,route_id,direction_id,service_id\nt1,Z,2,weekday\n"},
            {"trips": "trip_id,route_id,direction_id,service_id\nt1,missing,0,weekday\n"},
            {"routes": "route_id,route_short_name\nZ,10\nZ,10\n"},
            {"stop_times": "stop_id,trip_id,pickup_type\nabsent,t1,0\n"},
            {"calendar": "service_id,monday\n"},
        )
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            for n, change in enumerate(cases):
                with self.subTest(n=n):
                    fixture(base / "bad.zip", change)
                    out = base / ("bad" + str(n))
                    with self.assertRaises(gt.GeneratorError):
                        run(base / "bad.zip", out)
                    self.assertFalse(out.exists())
            fixture(base / "valid.zip")
            for date in ("2026-10-31", "2026-12-01"):
                with self.subTest(date=date):
                    with self.assertRaisesRegex(gt.GeneratorError, "does not include"):
                        run(base / "valid.zip", base / ("outside" + date), date)
                    self.assertFalse((base / ("outside" + date)).exists())
            for date in ("2026-11-01", "2026-11-30"):
                with self.subTest(date=date):
                    run(base / "valid.zip", base / ("edge" + date), date)
            with self.assertRaisesRegex(gt.GeneratorError, "requires a GTFS zip"):
                run(HERE / "fixtures" / "stops_sample.txt", base / "plain")
            with zipfile.ZipFile(base / "short.zip", "w") as archive:
                archive.writestr("stops.txt", "stop_id,stop_code,stop_lat,stop_lon\n"
                                 "a,1001,-43.5,172.6\n")
            with self.assertRaisesRegex(gt.GeneratorError, "requires routes.txt"):
                run(base / "short.zip", base / "short")

    def test_script_reports_feed_errors_without_traceback(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            with zipfile.ZipFile(base / "short.zip", "w") as archive:
                archive.writestr("stops.txt", "stop_id,stop_code,stop_lat,stop_lon\n"
                                 "a,1001,-43.5,172.6\n")
            result = subprocess.run(
                [sys.executable, str(HERE / "generate_tiles.py"), str(base / "short.zip"),
                 str(base / "out"), "--service-metadata"],
                capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stderr,
                             "error: --service-metadata requires routes.txt\n")
            self.assertFalse((base / "out").exists())

    def test_no_usable_keys_and_too_many_global_keys_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fixture(base / "none.zip", {
                "calendar_dates": "service_id,date,exception_type\nexception,20261118,2\n",
                "calendar": ("service_id,monday,tuesday,wednesday,thursday,friday,"
                             "saturday,sunday,start_date,end_date\n"
                             "weekday,0,0,0,0,0,0,0,20261101,20261130\n")})
            with self.assertRaisesRegex(gt.GeneratorError, "1..1296"):
                run(base / "none.zip", base / "none")
            fixture(base / "many.zip", {
                "routes": "route_id,route_short_name\n" + "".join(
                    "r%04d,10\n" % n for n in range(1297)),
                "trips": "trip_id,route_id,direction_id,service_id\n" + "".join(
                    "t%d,r%04d,0,weekday\n" % (n, n) for n in range(1297)),
                "stop_times": "stop_id,trip_id,pickup_type\n" + "".join(
                    "internal,t%d,0\n" % n for n in range(1297)),
            })
            with self.assertRaisesRegex(gt.GeneratorError, "1..1296"):
                run(base / "many.zip", base / "many")
            self.assertFalse((base / "many").exists())

    def test_calendar_removal_and_restricted_pickup_leave_unknown_not_complete(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fixture(base / "restricted.zip", {
                "stop_times": ("stop_id,trip_id,pickup_type\n"
                               "internal,t1,0\nother,t1,2\nthird,t2,3\n")})
            run(base / "restricted.zip", base / "site")
            root = tile(base / "site")
            self.assertEqual(decode(root), {1001: [0]})
            self.assertEqual(root["i"], ["00", None, None])
            self.assertEqual(root["p"], [])
            for pickup in ("2", "3"):
                fixture(base / "mixed.zip", {
                    "stop_times": ("stop_id,trip_id,pickup_type\n"
                                   "internal,t1,0\ninternal,t3,%s\nother,t1,0\n" % pickup)})
                run(base / "mixed.zip", base / ("mixed" + pickup))
                mixed = tile(base / ("mixed" + pickup))
                self.assertEqual(decode(mixed), {1001: [0], 1002: [0]})
                self.assertEqual(mixed["p"], [1001])
            fixture(base / "removed.zip", {
                "calendar_dates": "service_id,date,exception_type\nexception,20261118,2\n"})
            run(base / "removed.zip", base / "removed")
            self.assertEqual(decode(tile(base / "removed")), {1001: [0], 1002: [0]})

    def test_cap_preflight_keeps_published_tree_and_exact_boundary(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fixture(base / "a.zip")
            stops, _ = gt.load_stops(str(base / "a.zip"))
            service = svc.build(str(base / "a.zip"), stops, DATE, gt.stops_hash(stops))
            states, keys, digest = service
            member = gt.Stop(1001, -4350000, 17260000, "")
            metadata = svc.encode([member], states, {key: n for n, key in enumerate(keys)}, digest)
            size = len(gt.encode_tile(DATE, [member], metadata))
            exact = member._replace(name="x" * (4096 - size))
            self.assertEqual(len(gt.encode_tile(DATE, [exact], metadata)), 4096)
            out = base / "site"
            gt.write_output(str(out), {(0, 0): [exact]}, {"h": digest}, DATE, service=service)
            before = (out / "t" / "0" / "0.json").read_bytes()
            with self.assertRaisesRegex(gt.GeneratorError, "4097"):
                gt.write_output(str(out), {(0, 0): [exact], (0, 1): [
                    exact._replace(name=exact.name + "x")]}, {"h": digest}, DATE,
                    service=service)
            self.assertEqual((out / "t" / "0" / "0.json").read_bytes(), before)
            self.assertFalse((out / "t" / "0" / "1.json").exists())
            with self.assertRaisesRegex(gt.GeneratorError, "1296"):
                gt.write_output(str(out), {(0, 0): [exact]}, {"h": digest}, DATE,
                                service=(states, list(range(1297)), digest))


if __name__ == "__main__":
    unittest.main()
