"""Unit tests for generate_tiles.py (standard library only).

Run with: python3 -m unittest discover tools/stoptiles
"""

import contextlib
import io
import json
import os
import tempfile
import unittest
import zipfile
from pathlib import Path

import generate_tiles as gt

HERE = Path(__file__).resolve().parent
VECTORS = json.loads((HERE / "test_vectors.json").read_text(encoding="utf-8"))
FIXTURE = HERE / "fixtures" / "stops_sample.txt"

HEADER = ("stop_id,stop_code,stop_name,stop_desc,stop_lat,stop_lon,zone_id,"
          "stop_url,location_type,parent_station,platform_code")


def row(code, lat="-43.5", lon="172.6", name="Name", location_type="",
        stop_code=None):
    """A stops.txt row as the csv module would return it."""
    return {
        "stop_id": str(code),
        "stop_code": str(code) if stop_code is None else stop_code,
        "stop_name": name,
        "stop_desc": " ",
        "stop_lat": lat,
        "stop_lon": lon,
        "location_type": location_type,
    }


def stops_text(rows):
    lines = [HEADER]
    for r in rows:
        lines.append(",".join([
            r["stop_id"], r["stop_code"], '"%s"' % r["stop_name"], r["stop_desc"],
            r["stop_lat"], r["stop_lon"], "", "", r["location_type"], "", ""]))
    return "\n".join(lines) + "\n"


def make_zip(path, rows, extra=None):
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("stops.txt", stops_text(rows).encode("utf-8"))
        for name, data in (extra or {}).items():
            archive.writestr(name, data)


def run_generate(input_path, outdir, **kwargs):
    out = io.StringIO()
    meta = gt.generate(str(input_path), str(outdir), date="2026-11-12", out=out, **kwargs)
    return meta, out.getvalue()


def stop(code, lat, lon, name="n"):
    return gt.Stop(code, lat, lon, name)


class ContractVectorTests(unittest.TestCase):
    def test_e5_rounding_vectors(self):
        for case in VECTORS["e5Rounding"]:
            with self.subTest(deg=case["deg"]):
                self.assertEqual(gt.to_e5(case["deg"]), case["e5"])

    def test_e5_is_exact_for_long_decimals(self):
        # A float would turn this half-way value into something else.
        self.assertEqual(gt.to_e5("-43.5310049999999999999999"), -4353100)
        self.assertEqual(gt.to_e5("-43.5310050000000000000001"), -4353101)
        self.assertEqual(gt.to_e5("-43.531005"), -4353100)

    def test_e5_rejects_malformed_text(self):
        for text in ("", "abc", "1_0", "NaN", "Infinity", "1e5", "--1", "1,5"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                gt.to_e5(text)

    def test_tile_id_vectors(self):
        for case in VECTORS["tileId"]:
            with self.subTest(e5=case["e5"]):
                self.assertEqual(gt.tile_id(case["e5"]), case["tile"])
                if case["trap"]:
                    self.assertNotEqual(int(case["e5"] / 1000), case["tile"])

    def test_tile_id_vector_for_positive_longitude_and_trap_flags(self):
        self.assertTrue(any(c["trap"] for c in VECTORS["tileId"]))
        self.assertEqual(gt.tile_id(17263999), 17263)
        self.assertEqual(gt.tile_id(17264000), 17264)

    def test_buffer_constants_match_vectors(self):
        buffers = VECTORS["buffers"]
        self.assertEqual(gt.STEP_COUNT, buffers["steps"])
        self.assertEqual(gt.STEP_LAT_E5, buffers["stepLatE5"])
        self.assertEqual(gt.STEP_LON_E5, buffers["stepLonE5"])
        self.assertEqual(gt.CAP_LAT_E5, buffers["capLatE5"])
        self.assertEqual(gt.CAP_LON_E5, buffers["capLonE5"])
        self.assertEqual(gt.MIN_STOPS, buffers["minStops"])
        self.assertEqual(gt.MIN_STOPS, max(3 * gt.NEARBY_COUNT, 10))

    def test_membership_vectors_are_inclusive(self):
        for case in VECTORS["membership"]:
            with self.subTest(**case):
                lat_lo = case["ty"] * 1000
                lon_lo = case["tx"] * 1000
                is_member = (
                    lat_lo - case["bLat"] <= case["latE5"] <= lat_lo + 999 + case["bLat"]
                    and lon_lo - case["bLon"] <= case["lonE5"] <= lon_lo + 999 + case["bLon"])
                self.assertEqual(is_member, case["member"])

    def test_membership_vectors_against_generator(self):
        """With a single stop the generator widens to the cap, so only the cap
        vectors apply to tile_members; the other buffers are checked above."""
        for case in VECTORS["membership"]:
            if (case["bLat"], case["bLon"]) != (gt.CAP_LAT_E5, gt.CAP_LON_E5):
                continue
            with self.subTest(**case):
                s = stop(5000, case["latE5"], case["lonE5"])
                members = gt.tile_members([s], case["ty"], case["tx"])
                self.assertEqual(s in members, case["member"])

    def test_nearest_vectors(self):
        data = VECTORS["nearest"]
        stops = [gt.Stop(*s) for s in data["stops"]]
        for query in data["queries"]:
            with self.subTest(**{k: query[k] for k in ("latE5", "lonE5", "count")}):
                result = gt.nearest(stops, query["latE5"], query["lonE5"], query["count"])
                self.assertEqual([s.code for s in result], query["expected"])


class MembershipTests(unittest.TestCase):
    TY, TX = -4354, 17263
    LAT_LO = TY * 1000
    LON_LO = TX * 1000

    def inside(self, code):
        return stop(code, self.LAT_LO + 500, self.LON_LO + 500)

    def test_inclusive_cell_boundaries(self):
        corners = [
            stop(1, self.LAT_LO, self.LON_LO),
            stop(2, self.LAT_LO + 999, self.LON_LO + 999),
        ]
        self.assertEqual(len(gt.tile_members(corners, self.TY, self.TX)), 2)

    def test_step_one_buffer_is_inclusive(self):
        # Fill the tile to the minimum so it stops at k = 1.
        base = [stop(100 + i, self.LAT_LO + 500, self.LON_LO + 500) for i in range(gt.MIN_STOPS)]
        edges = {
            "lat low in": stop(1, self.LAT_LO - 360, self.LON_LO + 5),
            "lat low out": stop(2, self.LAT_LO - 361, self.LON_LO + 5),
            "lon high in": stop(3, self.LAT_LO + 5, self.LON_LO + 999 + 496),
            "lon high out": stop(4, self.LAT_LO + 5, self.LON_LO + 999 + 497),
        }
        members = gt.tile_members(base + list(edges.values()), self.TY, self.TX)
        self.assertIn(edges["lat low in"], members)
        self.assertNotIn(edges["lat low out"], members)
        self.assertIn(edges["lon high in"], members)
        self.assertNotIn(edges["lon high out"], members)

    def test_stop_near_cell_boundary_is_in_both_tiles(self):
        s = stop(2107, self.LAT_LO + 999, self.LON_LO + 999)  # last E5 of the cell
        tiles = gt.build_tiles([s])
        self.assertIn(s, tiles[(self.TY, self.TX)])
        self.assertIn(s, tiles[(self.TY + 1, self.TX)])
        self.assertIn(s, tiles[(self.TY, self.TX + 1)])
        self.assertIn(s, tiles[(self.TY - 1, self.TX - 1)])

    def test_widening_stops_at_fifteen(self):
        own = [self.inside(100 + i) for i in range(5)]
        # Only inside the k = 2 buffer (720) but outside k = 1 (360).
        ring = [stop(200 + i, self.LAT_LO - 700, self.LON_LO + 500) for i in range(10)]
        far = stop(300, self.LAT_LO - 1000, self.LON_LO + 500)  # needs k = 3
        members = gt.tile_members(own + ring + [far], self.TY, self.TX)
        self.assertEqual(len(members), 15)
        self.assertNotIn(far, members)

    def test_not_widened_beyond_what_is_needed(self):
        own = [self.inside(100 + i) for i in range(15)]
        ring = stop(200, self.LAT_LO - 300, self.LON_LO + 500)  # inside k = 1
        outer = stop(201, self.LAT_LO - 500, self.LON_LO + 500)  # needs k = 2
        members = gt.tile_members(own + [ring, outer], self.TY, self.TX)
        self.assertIn(ring, members)
        self.assertNotIn(outer, members)

    def test_widening_continues_to_the_cap(self):
        own = [self.inside(100)]
        between = stop(200, self.LAT_LO - 2600, self.LON_LO + 500)  # after k = 7 (2520)
        on_cap = stop(201, self.LAT_LO - 2698, self.LON_LO + 500)
        past_cap = stop(202, self.LAT_LO - 2699, self.LON_LO + 500)
        lon_on_cap = stop(203, self.LAT_LO + 500, self.LON_LO + 999 + 3719)
        lon_past_cap = stop(204, self.LAT_LO + 500, self.LON_LO + 999 + 3720)
        members = gt.tile_members(
            own + [between, on_cap, past_cap, lon_on_cap, lon_past_cap], self.TY, self.TX)
        self.assertEqual(
            sorted(s.code for s in members), [100, 200, 201, 203])

    def test_cap_used_regardless_of_count_after_step_seven(self):
        # 14 stops: never reaches 15, so the cap (not k = 7) decides.
        stops = [stop(100 + i, self.LAT_LO - 2600, self.LON_LO + 500) for i in range(14)]
        self.assertEqual(len(gt.tile_members(stops, self.TY, self.TX)), 14)

    def test_tile_stops_sorted_by_code(self):
        stops = [stop(300, -4353500, 17263500), stop(100, -4353500, 17263600),
                 stop(200, -4353500, 17263700)]
        members = gt.build_tiles(stops)[(self.TY, self.TX)]
        self.assertEqual([s.code for s in members], [100, 200, 300])


class CoverageTests(unittest.TestCase):
    def test_cells_just_inside_and_outside_the_margin(self):
        lat = -4352698  # cell ty=-4350 starts exactly 2698 above this stop
        lon = 17263500
        cells = gt.covered_cells([stop(2107, lat, lon)])
        self.assertIn((-4350, 17263), cells)
        self.assertNotIn((-4349, 17263), cells)
        cells = gt.covered_cells([stop(2107, lat - 1, lon)])
        self.assertNotIn((-4350, 17263), cells)

    def test_lon_margin_edges(self):
        lat = -4353500

        def tx_range(lon):
            txs = [tx for _, tx in gt.covered_cells([stop(1000, lat, lon)])]
            return min(txs), max(txs)

        # lon - 3719 lands exactly on a cell start: that cell is still covered.
        self.assertEqual(tx_range(17262719)[0], 17259)
        self.assertEqual(tx_range(17262718)[0], 17258)
        # lon + 3719 lands exactly on a cell start: that cell is covered.
        self.assertEqual(tx_range(17263281)[1], 17267)
        self.assertEqual(tx_range(17263280)[1], 17266)

    def test_covered_cells_negative_floor(self):
        cells = gt.covered_cells([stop(1000, -4357000, 17263000)])
        self.assertEqual(min(ty for ty, _ in cells), -4360)  # floor(-4359698 / 1000)
        self.assertEqual(max(ty for ty, _ in cells), -4355)  # floor(-4354302 / 1000)

    def test_empty_tile_is_encoded_with_empty_array(self):
        self.assertEqual(
            gt.encode_tile("2026-11-12", []), b'{"v":1,"g":"2026-11-12","s":[]}')

    def test_every_covered_cell_gets_a_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            stops_path = Path(tmp) / "stops.txt"
            stops_path.write_text(stops_text([row(2107, "-43.53100", "172.63700")]), encoding="utf-8")
            out = Path(tmp) / "site"
            run_generate(stops_path, out)
            files = sorted(p for p in (out / "t").rglob("*.json"))
            self.assertEqual(len(files), len(gt.covered_cells([stop(2107, -4353100, 17263700)])))
            self.assertTrue((out / "t" / "-4354" / "17263.json").is_file())
            self.assertFalse((out / "t" / "-4350" / "17263.json").exists())


class FilterTests(unittest.TestCase):
    def parse(self, rows):
        return gt.parse_stops(rows)

    def test_keeps_blank_and_zero_location_type(self):
        stops, skipped = self.parse([row(2000), row(2001, location_type="0")])
        self.assertEqual([s.code for s in stops], [2000, 2001])
        self.assertEqual(sum(skipped.values()), 0)

    def test_skips_non_zero_location_type(self):
        stops, skipped = self.parse([row(2000, location_type="1"), row(2001, location_type="x"),
                                     row(2002)])
        self.assertEqual([s.code for s in stops], [2002])
        self.assertEqual(skipped["location_type"], 2)

    def test_skips_missing_or_non_numeric_stop_code(self):
        rows = [row(2000, stop_code=""), row(2001, stop_code="A12"), row(2002, stop_code="12.5"),
                row(2003, stop_code="-5"), row(2004)]
        stops, skipped = self.parse(rows)
        self.assertEqual([s.code for s in stops], [2004])
        self.assertEqual(skipped["stop_code"], 4)

    def test_skips_codes_outside_range(self):
        rows = [row(999), row(1000), row(99999), row(100000)]
        stops, skipped = self.parse(rows)
        self.assertEqual([s.code for s in stops], [1000, 99999])
        self.assertEqual(skipped["stop_code_range"], 2)

    def test_skips_bad_coordinates(self):
        rows = [row(2000, lat=""), row(2001, lon="abc"), row(2002, lat="91"),
                row(2003, lon="181"), row(2004, lat="NaN"), row(2005)]
        stops, skipped = self.parse(rows)
        self.assertEqual([s.code for s in stops], [2005])
        self.assertEqual(skipped["coordinates"], 5)

    def test_duplicate_stop_code_fails(self):
        with self.assertRaises(gt.GeneratorError) as ctx:
            self.parse([row(2000), row(2000, lat="-43.6")])
        self.assertIn("duplicate stop_code 2000", str(ctx.exception))

    def test_ignores_platform_zone_and_desc(self):
        r = row(2000)
        r.update(platform_code="3", zone_id="1", stop_desc="something")
        stops, _ = self.parse([r])
        self.assertEqual(stops, [gt.Stop(2000, -4350000, 17260000, "Name")])

    def test_name_is_raw(self):
        raw = "Bus Foo near Bar (Platform 3) a-very-long name " + "x" * 80
        stops, _ = self.parse([row(2000, name=raw)])
        self.assertEqual(stops[0].name, raw)

    def test_stops_sorted_by_code(self):
        stops, _ = self.parse([row(3000), row(2000), row(2500)])
        self.assertEqual([s.code for s in stops], [2000, 2500, 3000])


class OutputTests(unittest.TestCase):
    def test_fixture_end_to_end(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "site"
            meta, text = run_generate(FIXTURE, out, etag='"abc"')
            self.assertEqual(meta["n"], 4)
            self.assertEqual(meta["e"], '"abc"')
            self.assertEqual(list(meta), ["v", "g", "gv", "n", "h", "e", "attribution"])
            self.assertEqual(meta["gv"], gt.GENERATOR_VERSION)
            raw = (out / "meta.json").read_bytes()
            self.assertEqual(json.loads(raw), meta)
            self.assertNotIn(b" ", raw.replace(meta["attribution"].encode(), b""))
            tile = (out / "t" / "-4354" / "17263.json").read_bytes()
            self.assertEqual(
                tile,
                '{"v":1,"g":"2026-11-12","s":[[2107,-4353100,17263700,"Synthetic Stop One"],'
                '[2108,-4353105,17263705,"Synthetic Stop Two near Somewhere"]]}'.encode("utf-8"),
            )
            for key in ("tiles", "total bytes", "median tile bytes", "max tile bytes",
                        "max stops per tile", "stops", "hash", "gv"):
                self.assertIn("%s: " % key, text)
            for rule in gt.SKIP_RULES:
                self.assertIn("skipped (%s): 0" % rule, text)

    def test_rapaki_is_utf8_without_escape(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "site"
            run_generate(FIXTURE, out)
            tile = (out / "t" / "-4360" / "17270.json").read_bytes()
            self.assertIn("Rāpaki".encode("utf-8"), tile)
            self.assertNotIn(b"\\u", tile)

    def test_tile_over_4096_bytes_fails_and_main_exits_non_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            stops_path = Path(tmp) / "stops.txt"
            stops_path.write_text(stops_text([row(2000, name="x" * 5000)]), encoding="utf-8")
            out = Path(tmp) / "site"
            with self.assertRaises(gt.GeneratorError):
                run_generate(stops_path, out)
            self.assertFalse((out / "t").exists())
            err = io.StringIO()
            with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(gt.main([str(stops_path), str(out)]), 1)
            self.assertIn("4096", err.getvalue())

    def test_tile_of_exactly_4096_bytes_is_accepted(self):
        base = len(gt.encode_tile("2026-11-12", [stop(2000, -4350000, 17260000, "")]))
        name = "x" * (gt.MAX_TILE_BYTES - base)
        with tempfile.TemporaryDirectory() as tmp:
            stops_path = Path(tmp) / "stops.txt"
            stops_path.write_text(stops_text([row(2000, name=name)]), encoding="utf-8")
            meta, _ = run_generate(stops_path, Path(tmp) / "site")
            self.assertEqual(meta["n"], 1)

    def test_zero_stops_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            stops_path = Path(tmp) / "stops.txt"
            stops_path.write_text(stops_text([row(2000, location_type="1")]), encoding="utf-8")
            with self.assertRaises(gt.GeneratorError):
                run_generate(stops_path, Path(tmp) / "site")
            with contextlib.redirect_stderr(io.StringIO()), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(gt.main([str(stops_path), str(Path(tmp) / "site")]), 1)

    def test_duplicate_code_makes_main_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            stops_path = Path(tmp) / "stops.txt"
            stops_path.write_text(stops_text([row(2000), row(2000)]), encoding="utf-8")
            err = io.StringIO()
            with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(gt.main([str(stops_path), str(Path(tmp) / "site")]), 1)
            self.assertIn("duplicate", err.getvalue())

    def test_hash_unchanged_when_only_other_zip_files_change(self):
        rows = [row(2000, name="Alpha"), row(2001, lat="-43.51", name="Beta")]
        with tempfile.TemporaryDirectory() as tmp:
            first = Path(tmp) / "a.zip"
            second = Path(tmp) / "b.zip"
            make_zip(first, rows, {"trips.txt": "trip_id\n1\n", "feed_info.txt": "v1\n"})
            make_zip(second, rows, {"trips.txt": "trip_id\n1\n2\n", "calendar.txt": "x\n"})
            meta_a, _ = run_generate(first, Path(tmp) / "oa")
            meta_b, _ = run_generate(second, Path(tmp) / "ob")
            self.assertEqual(meta_a["h"], meta_b["h"])

    def test_hash_unchanged_by_row_order_but_changes_with_name(self):
        rows = [row(2000, name="Alpha"), row(2001, lat="-43.51", name="Beta")]
        renamed = [row(2000, name="Alpha"), row(2001, lat="-43.51", name="Gamma")]
        with tempfile.TemporaryDirectory() as tmp:
            paths = {}
            for key, data in (("base", rows), ("reversed", rows[::-1]), ("renamed", renamed)):
                paths[key] = Path(tmp) / (key + ".zip")
                make_zip(paths[key], data)
            hashes = {k: run_generate(p, Path(tmp) / k)[0]["h"] for k, p in paths.items()}
            self.assertEqual(hashes["base"], hashes["reversed"])
            self.assertNotEqual(hashes["base"], hashes["renamed"])

    def test_hash_is_sha256_of_compact_utf8_list(self):
        import hashlib
        stops = [gt.Stop(2000, -4350000, 17260000, "Rāpaki")]
        payload = '[[2000,-4350000,17260000,"Rāpaki"]]'.encode("utf-8")
        self.assertEqual(gt.stops_hash(stops), hashlib.sha256(payload).hexdigest())

    def test_zip_and_plain_stops_txt_give_same_result(self):
        with tempfile.TemporaryDirectory() as tmp:
            zip_path = Path(tmp) / "gtfs.zip"
            make_zip(zip_path, [row(2000)])
            txt_path = Path(tmp) / "stops.txt"
            txt_path.write_text(stops_text([row(2000)]), encoding="utf-8")
            self.assertEqual(run_generate(zip_path, Path(tmp) / "a")[0]["h"],
                             run_generate(txt_path, Path(tmp) / "b")[0]["h"])

    def test_zip_without_stops_txt_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            zip_path = Path(tmp) / "gtfs.zip"
            with zipfile.ZipFile(zip_path, "w") as archive:
                archive.writestr("routes.txt", "x\n")
            with self.assertRaises(gt.GeneratorError):
                run_generate(zip_path, Path(tmp) / "site")

    def test_previous_meta_and_static_and_stale_tiles(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "site"
            static = Path(tmp) / "static"
            static.mkdir()
            (static / "index.html").write_text("hi", encoding="utf-8")
            (out / "t" / "1").mkdir(parents=True)
            (out / "t" / "1" / "2.json").write_text("stale", encoding="utf-8")
            previous = Path(tmp) / "old-meta.json"
            previous.write_text('{"v":1,"n":7,"h":"oldhash","gv":0}', encoding="utf-8")
            _, text = run_generate(FIXTURE, out, previous_meta=str(previous),
                                   static_dir=str(static))
            self.assertIn("previous meta: n=7 h=oldhash gv=0", text)
            self.assertIn("new meta:      n=4", text)
            self.assertEqual((out / "index.html").read_text(encoding="utf-8"), "hi")
            self.assertFalse((out / "t" / "1" / "2.json").exists())

    def test_static_dir_cannot_restore_stale_tiles(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "site"
            static = Path(tmp) / "static"
            (static / "t" / "1").mkdir(parents=True)
            (static / "t" / "1" / "2.json").write_text("stale", encoding="utf-8")
            (static / "index.html").write_text("hi", encoding="utf-8")
            run_generate(FIXTURE, out, static_dir=str(static))
            self.assertEqual((out / "index.html").read_text(encoding="utf-8"), "hi")
            self.assertFalse((out / "t" / "1" / "2.json").exists())
            for tile in (out / "t").rglob("*.json"):
                self.assertNotEqual(tile.read_text(encoding="utf-8"), "stale")

    def test_previous_meta_inside_outdir_is_read_before_overwrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "site"
            out.mkdir()
            (out / "meta.json").write_text('{"v":1,"n":7,"h":"oldhash","gv":0}',
                                           encoding="utf-8")
            meta, text = run_generate(FIXTURE, out, previous_meta=str(out / "meta.json"))
            self.assertIn("previous meta: n=7 h=oldhash gv=0", text)
            self.assertIn("new meta:      n=4 h=%s" % meta["h"], text)

    def test_unreadable_previous_meta_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, text = run_generate(FIXTURE, Path(tmp) / "site",
                                   previous_meta=str(Path(tmp) / "missing.json"))
            self.assertIn("previous meta: unreadable", text)

    def test_main_runs_and_prints_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = gt.main([str(FIXTURE), str(Path(tmp) / "site"), "--date", "2026-11-12"])
            self.assertEqual(code, 0)
            self.assertIn("hash: ", out.getvalue())

    def test_main_rejects_bad_date(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            gt.main([str(FIXTURE), "unused", "--date", "12/11/2026"])


if __name__ == "__main__":
    unittest.main()
