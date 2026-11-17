"""Synthetic-only tests for the offline service contract."""
import base64
import json
import os
import unittest

import analyse_service_keys as audit
import generate_tiles as tiles


def stop(sid, code):
    return {"stop_id": sid, "stop_code": str(code)}


def trip(tid, route="r", direction="0", head="Centre"):
    return {"trip_id": tid, "route_id": route, "direction_id": direction,
            "trip_headsign": head}


def visit(sid, tid, pickup="0", head=""):
    return {"stop_id": sid, "trip_id": tid, "pickup_type": pickup,
            "stop_headsign": head}


class AuditTests(unittest.TestCase):
    def test_joins_use_stop_id_not_public_code_and_reliability(self):
        source = [stop("internal-a", 1001), stop("internal-b", 1002),
                  stop("internal-c", 1003), stop("internal-d", 1004)]
        selected = [tiles.Stop(code, -4350000, 17260000, "Synthetic")
                    for code in range(1001, 1005)]
        keys, bad, counts, _ = audit.service_sets(
            source, [visit("internal-a", "t"), visit("internal-b", "t"),
                     visit("internal-b", "missing"), visit("internal-c", "missing"),
                     visit("not-a-stop", "t")],
            [trip("t")], [{"route_id": "r", "route_short_name": "10"}])
        self.assertEqual(counts["orphan_stop_rows"], 1)
        self.assertEqual(counts["orphan_trip_rows"], 2)
        self.assertEqual(audit.classify(selected, source, keys, bad),
                         {1001: ("complete", {("r", 0)}),
                          1002: ("partial", {("r", 0)}),
                          1003: ("unknown", set()), 1004: ("unknown", set())})

    def test_loops_directions_variants_and_pickup(self):
        keys, bad, counts, _ = audit.service_sets(
            [stop("s", 1001), stop("other", 1002)],
            [visit("s", "a"), visit("s", "a", head="East"),
             visit("s", "b"), visit("s", "c", pickup="1"),
             visit("other", "invalid")],
            [trip("a", head="Centre"), trip("b", head="Express"),
             trip("c", direction="1"), trip("invalid", direction="")],
            [{"route_id": "r", "route_short_name": "X"}])
        self.assertEqual(keys["s"], {("r", 0)})
        self.assertEqual(counts["repeated_trip_stop_pairs"], 1)
        self.assertEqual(counts["keys_with_multiple_trip_headsigns"], 1)
        self.assertEqual(counts["keys_with_multiple_stop_headsigns"], 1)
        self.assertEqual(counts["restricted_pickup_rows"], 1)
        self.assertEqual(counts["stops_with_restricted_only_keys"], 1)
        self.assertEqual(counts["invalid_direction_rows"], 1)
        self.assertEqual(bad, {"other"})

    def test_unknown_stays_visible_and_coverage(self):
        stops = [tiles.Stop(1001 + n, 0, n, "Synthetic") for n in range(4)]
        data = {1001: ("complete", {("a", 0)}),
                1002: ("complete", {("a", 0)}),
                1003: ("partial", {("a", 0)}),
                1004: ("unknown", set())}
        self.assertEqual(audit.select(stops, data, 0, 0),
                         [1001, 1003, 1004])

    def test_tile_local_indices_and_four_field_rows(self):
        stops = [tiles.Stop(1001, 0, 0, "Ā name"),
                 tiles.Stop(1002, 0, 1, "B")]
        data = {1001: ("complete", {("r", 0), ("r", 1)}),
                1002: ("partial", {("r", 1)})}
        sizes = audit.payloads("2026-11-18", stops, data)
        self.assertGreater(sizes["naive"], sizes["legacy"])
        unique = sorted({key for _, keys in data.values() for key in keys})
        mask = base64.b64encode((1 << unique.index(("r", 1))).to_bytes(1, "little"))
        self.assertEqual(base64.b64decode(mask), b"\x02")
        root = json.loads(tiles.encode_tile("2026-11-18", stops))
        self.assertTrue(all(len(row) == 4 for row in root["s"]))

    def test_shared_contract_vectors(self):
        with open(os.path.join(os.path.dirname(__file__), "service_key_vectors.json"),
                  encoding="utf-8") as stream:
            vectors = json.load(stream)
        for case in vectors["cases"]:
            with self.subTest(case["name"]):
                decoded = audit.decode_metadata(case["tile"], "2026-11-18")
                expected = case["expected"]
                if expected is None:
                    self.assertIsNone(decoded)
                else:
                    self.assertEqual(
                        {str(code): [state, [list(k) for k in sorted(keys)]]
                         for code, (state, keys) in decoded.items()}, expected)
        self.assertIsNone(audit.decode_metadata(
            vectors["cases"][0]["tile"], "2026-11-19"))


if __name__ == "__main__":
    unittest.main()
