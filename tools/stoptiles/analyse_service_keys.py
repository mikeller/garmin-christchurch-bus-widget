#!/usr/bin/env python3
"""Offline GTFS service-key audit. Usage: python3 tools/stoptiles/analyse_service_keys.py GTFS.zip

Prints aggregate JSON only; never prints feed rows. Requires Python stdlib.
"""
import argparse
import base64
import csv
import hashlib
import io
import json
import math
import re
import zipfile
from collections import Counter, defaultdict

import generate_tiles as tiles


def rows(archive, name):
    with archive.open(name + ".txt") as stream:
        reader = csv.DictReader(io.TextIOWrapper(stream, encoding="utf-8-sig", newline=""))
        yield from reader


def service_sets(stops, times, trips, routes):
    """Return keys by public code, reliability, and join diagnostics.

    Every stop_times row must resolve by stop_id and trip_id to a known route
    with direction 0 or 1. A broken row contaminates that stop, not the feed.
    """
    counts = Counter()
    stop_ids = {}
    ambiguous_stops = set()
    for row in stops:
        sid = row["stop_id"]
        if sid in stop_ids:
            counts["duplicate_stop_id"] += 1
            ambiguous_stops.add(sid)
        stop_ids[sid] = row
    route_ids = {}
    ambiguous_routes = set()
    short_names = defaultdict(set)
    for row in routes:
        rid = row["route_id"]
        if rid in route_ids:
            counts["duplicate_route_id"] += 1
            ambiguous_routes.add(rid)
        route_ids[rid] = row
        short_names[row["route_short_name"]].add(rid)
    counts["short_name_collisions"] = sum(len(v) > 1 for v in short_names.values())
    trip_ids = {}
    ambiguous_trips = set()
    for row in trips:
        tid = row["trip_id"]
        if tid in trip_ids:
            counts["duplicate_trip_id"] += 1
            ambiguous_trips.add(tid)
        trip_ids[tid] = row
    keys = defaultdict(set)
    bad = set()
    visits = defaultdict(lambda: defaultdict(int))
    heads = defaultdict(set)
    trip_heads = defaultdict(set)
    stop_heads = defaultdict(set)
    restricted = defaultdict(set)
    for row in times:
        counts["stop_time_rows"] += 1
        sid, tid = row["stop_id"], row["trip_id"]
        if sid not in stop_ids:
            counts["orphan_stop_rows"] += 1
            continue
        if sid in ambiguous_stops:
            bad.add(sid)
            continue
        trip = trip_ids.get(tid)
        if trip is None:
            counts["orphan_trip_rows"] += 1
            bad.add(sid)
            continue
        if tid in ambiguous_trips:
            bad.add(sid)
            continue
        route = route_ids.get(trip["route_id"])
        if route is None:
            counts["orphan_route_rows"] += 1
            bad.add(sid)
            continue
        if trip["route_id"] in ambiguous_routes:
            bad.add(sid)
            continue
        direction = trip["direction_id"]
        if direction not in ("0", "1"):
            counts["invalid_direction_rows"] += 1
            bad.add(sid)
            continue
        if row.get("pickup_type", "") not in ("", "0"):
            counts["restricted_pickup_rows"] += 1
            restricted[sid].add((trip["route_id"], int(direction)))
            # A no-pickup visit cannot prove the service is boardable. If a
            # valid visit also exists it contributes its key normally.
            continue
        key = (trip["route_id"], int(direction))
        keys[sid].add(key)
        visits[tid][sid] += 1
        heads[key].add((trip.get("trip_headsign", ""), row.get("stop_headsign", "")))
        trip_heads[key].add(trip.get("trip_headsign", ""))
        stop_heads[key].add(row.get("stop_headsign", ""))
    counts["repeated_trip_stop_pairs"] = sum(n - 1 for v in visits.values()
                                             for n in v.values() if n > 1)
    counts["keys_with_multiple_headsign_pairs"] = sum(len(v) > 1 for v in heads.values())
    counts["keys_with_multiple_trip_headsigns"] = sum(len(v) > 1 for v in trip_heads.values())
    counts["keys_with_multiple_stop_headsigns"] = sum(len(v) > 1 for v in stop_heads.values())
    counts["stops_with_restricted_only_keys"] = sum(
        bool(restricted[sid] - keys[sid]) for sid in restricted)
    return keys, bad, counts, stop_ids


def classify(selected, source_rows, keys, bad):
    """Missing or ambiguous stop_id is unknown; partially joined is partial."""
    by_code = defaultdict(list)
    for row in source_rows:
        if row.get("stop_code", "").isascii() and row.get("stop_code", "").isdigit():
            by_code[int(row["stop_code"])].append(row["stop_id"])
    result = {}
    for stop in selected:
        ids = by_code[stop.code]
        if len(ids) != 1 or not keys[ids[0]]:
            result[stop.code] = ("unknown", set())
        elif ids[0] in bad:
            result[stop.code] = ("partial", keys[ids[0]])
        else:
            result[stop.code] = ("complete", keys[ids[0]])
    return result


def payloads(date, members, data):
    """Four candidate UTF-8 wire sizes; rows in s remain exactly four fields."""
    root = json.loads(tiles.encode_tile(date, members))
    unique = sorted({key for s in members for key in data[s.code][1]})
    index = {key: n for n, key in enumerate(unique)}
    known = [s for s in members if data[s.code][0] != "unknown"]
    partial = [s.code for s in known if data[s.code][0] == "partial"]
    common = {"m": 1, "sh": "0" * 64,
              "k": [[rid, direction] for rid, direction in unique],
              "p": partial}
    naive = dict(root, m=1, sh="0" * 64,
                 a=[[s.code, [[rid, d] for rid, d in sorted(data[s.code][1])]]
                    for s in known], p=partial)
    indexed = dict(root, **common, i=[[s.code, [index[key] for key in sorted(data[s.code][1])]]
                                       for s in known])
    width = (len(unique) + 7) // 8
    bits = dict(root, **common, b=[
        [s.code, base64.b64encode(sum(1 << index[key] for key in data[s.code][1])
                                  .to_bytes(width, "little")).decode("ascii")]
        for s in known])
    def size(body):
        return len(json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
    return {name: size(body) for name, body in
            (("legacy", root), ("naive", naive), ("index", indexed), ("bitset", bits))}


def decode_metadata(root, expected_generation=None, expected_hash=None):
    """Reference contract decoder: None means all stops remain visible."""
    if (not isinstance(root, dict) or type(root.get("v")) is not int or
            root["v"] != 1 or type(root.get("m")) is not int or
            root["m"] != 1 or not isinstance(root.get("g"), str) or
            not isinstance(root.get("sh"), str) or
            not re.fullmatch("[0-9a-f]{64}", root["sh"]) or
            (expected_hash is not None and root["sh"] != expected_hash) or
            (expected_generation is not None and root["g"] != expected_generation)):
        return None
    try:
        stops = root["s"]
        codes = [row[0] for row in stops]
        if (not isinstance(stops, list) or any(not isinstance(row, list) or
                len(row) != 4 or type(row[0]) is not int or
                not 1000 <= row[0] <= 99999 for row in stops)
                or len(set(codes)) != len(codes)):
            return None
        dictionary = root["k"]
        entries = root["i"]
        partial = root["p"]
        if not all(isinstance(x, list) for x in (dictionary, entries, partial)):
            return None
        keys = []
        for key in dictionary:
            if (not isinstance(key, list) or len(key) != 2 or
                    not isinstance(key[0], str) or not key[0] or
                    type(key[1]) is not int or key[1] not in (0, 1)):
                return None
            keys.append(tuple(key))
        if keys != sorted(set(keys)):
            return None
        known = {}
        for row in entries:
            if not isinstance(row, list) or len(row) != 2:
                return None
            code, indices = row
            if (type(code) is not int or code not in codes or code in known or
                    not isinstance(indices, list) or not indices or
                    any(type(n) is not int or n < 0 or n >= len(keys) for n in indices)
                    or indices != sorted(set(indices))):
                return None
            known[code] = {keys[n] for n in indices}
        if (list(known) != sorted(known) or
                any(type(code) is not int or code not in known for code in partial)
                or partial != sorted(set(partial))):
            return None
        return {code: (("partial" if code in partial else "complete"), value)
                for code, value in known.items()}
    except (KeyError, TypeError, ValueError):
        return None


def select(stops, data, lat, lon, limit=5):
    """Nearest-first, keep unknown/partial visible; known keys add coverage."""
    covered = set()
    retained = []
    for stop in tiles.nearest(stops, lat, lon, len(stops)):
        state, keys = data[stop.code]
        if state != "complete" or keys - covered:
            retained.append(stop.code)
            if state == "complete":
                covered.update(keys)
            if len(retained) == limit:
                break
    return retained


def coverage(stops, members, data, lat, lon):
    full = [s for s in stops if abs(s.lat - lat) <= tiles.CAP_LAT_E5
            and abs(s.lon - lon) <= tiles.CAP_LON_E5]
    reference = select(full, data, lat, lon)
    current = select(members, data, lat, lon)
    first15 = select(tiles.nearest(members, lat, lon, 15), data, lat, lon)
    return reference, current, first15


def percentile(values):
    return sorted(values)[math.ceil(len(values) * .95) - 1]


def analyse(path, samples=True):
    with open(path, "rb") as handle:
        digest = hashlib.file_digest(handle, "sha256").hexdigest()
    with zipfile.ZipFile(path) as archive:
        source = list(rows(archive, "stops"))
        selected, skipped = tiles.parse_stops(source)
        trip_rows = list(rows(archive, "trips"))
        keys, bad, counts, stop_ids = service_sets(
            source, rows(archive, "stop_times"), trip_rows,
            rows(archive, "routes"))
        service_dates = [r for r in rows(archive, "calendar")]
        exceptions = [r for r in rows(archive, "calendar_dates")]
        feed_info = list(rows(archive, "feed_info"))
    calendar_ids = {r["service_id"] for r in service_dates}
    exception_ids = {r["service_id"] for r in exceptions}
    counts["trips_without_calendar_or_exception"] = sum(
        r["service_id"] not in calendar_ids | exception_ids for r in trip_rows)
    data = classify(selected, source, keys, bad)
    membership = tiles.build_tiles(selected)
    sizes = defaultdict(list)
    worst = defaultdict(list)
    per_tile = []
    for cell, members in membership.items():
        measured = payloads("2026-11-18", members, data)
        per_tile.append([*cell, len(members), *(measured[name] for name in
                         ("legacy", "naive", "index", "bitset"))])
        for name, size in measured.items():
            sizes[name].append(size)
            worst[name].append((size, cell, len(members)))
    probes = Counter()
    examples = []
    if samples:
        for (ty, tx), members in membership.items():
            lo_lat, lo_lon = ty * 1000, tx * 1000
            for lat, lon in ((lo_lat + 500, lo_lon + 500),
                             (lo_lat, lo_lon), (lo_lat + 999, lo_lon),
                             (lo_lat, lo_lon + 999), (lo_lat + 999, lo_lon + 999)):
                reference, current, first15 = coverage(selected, members, data, lat, lon)
                probes["total"] += 1
                probes["tile_mismatch"] += current != reference
                probes["first15_mismatch"] += first15 != current
                probes["short_tile"] += len(members) < 15
                if first15 != current and len(examples) < 5:
                    examples.append([ty, tx, lat - lo_lat, lon - lo_lon])
    return {
        "sha256": digest, "selected": len(selected), "source_stops": len(source),
        "skip": skipped, "join": dict(counts),
        "states": dict(Counter(state for state, _ in data.values())),
        "key_count": len({k for _, (_, ks) in data.items() for k in ks}),
        "max_keys_per_stop": max((len(ks) for _, ks in data.values()), default=0),
        "calendar": {"start": min((r["start_date"] for r in service_dates), default=None),
                     "end": max((r["end_date"] for r in service_dates), default=None),
                     "exception_start": min((r["date"] for r in exceptions), default=None),
                     "exception_end": max((r["date"] for r in exceptions), default=None),
                     "feed_info": [{k: v for k, v in row.items()
                                    if k in ("feed_start_date", "feed_end_date")}
                                   for row in feed_info]},
        "tiles": len(membership),
        "per_tile_columns": ["ty", "tx", "stops", "legacy", "naive", "index", "bitset"],
        "per_tile": per_tile,
        "sizes": {name: {"max": max(values), "p95": percentile(values),
                         "overflow": sum(n > 4096 for n in values),
                         "worst": sorted(worst[name], reverse=True)[:3]}
                  for name, values in sizes.items()},
        "probes": dict(probes), "first15_examples": examples,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("zip", help="local GTFS zip")
    parser.add_argument("--skip-probes", action="store_true", help="skip coverage probes")
    args = parser.parse_args()
    print(json.dumps(analyse(args.zip, not args.skip_probes), indent=2, sort_keys=True))
