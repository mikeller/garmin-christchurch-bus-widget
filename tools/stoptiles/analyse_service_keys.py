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
import statistics
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


ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz"
GLOBAL_ENCODINGS = ("global_pairs", "global_parallel", "global_base64",
                    "global_hex", "global_sets", "global_base36")


def base36(n):
    return ALPHABET[n // 36] + ALPHABET[n % 36]


def global_payloads(date, members, data, numbering, service_hash="0" * 64):
    """Build complete synthetic tiles, with no route strings on the wire."""
    if len(numbering) > 1296 or sorted(numbering.values()) != list(range(len(numbering))):
        raise ValueError("two base-36 digits support at most 1296 global keys")
    root = json.loads(tiles.encode_tile(date, members))
    root.update(m=2, sh=service_hash, K=len(numbering))
    partial = [s.code for s in members if data[s.code][0] == "partial"]
    # p is mandatory even when empty; unknown has null in aligned forms and
    # no entry in code-keyed forms.
    root["p"] = partial
    known = [s for s in members if data[s.code][0] != "unknown"]
    indices = {s.code: sorted(numbering[key] for key in data[s.code][1])
               for s in known}
    width = (len(numbering) + 7) // 8
    masks = {code: sum(1 << n for n in values).to_bytes(width, "little")
             for code, values in indices.items()}
    distinct = sorted({tuple(values) for values in indices.values()})
    set_index = {value: n for n, value in enumerate(distinct)}
    return {
        "global_pairs": dict(root, i=[[s.code, indices[s.code]] for s in known]),
        "global_parallel": dict(root, i=[indices.get(s.code) for s in members]),
        "global_base64": dict(root, b=[
            [s.code, base64.b64encode(masks[s.code]).decode("ascii")]
            for s in known]),
        "global_hex": dict(root, b=[[s.code, masks[s.code].hex()] for s in known]),
        "global_sets": dict(root, q=[list(values) for values in distinct],
                            i=[set_index.get(tuple(indices[s.code]))
                               if s.code in indices else None for s in members]),
        "global_base36": dict(root, i=[
            "".join(base36(n) for n in indices[s.code])
            if s.code in indices else None for s in members]),
    }


def decode_global(root, encoding, expected_hash=None):
    """Return stop-code to (state, global indices); None means fail open."""
    try:
        if (type(root["v"]) is not int or root["v"] != 1 or
                type(root["m"]) is not int or root["m"] != 2 or
                type(root["K"]) is not int or not 0 < root["K"] <= 1296 or
                not isinstance(root["g"], str) or
                not isinstance(root["sh"], str) or
                not re.fullmatch("[0-9a-f]{64}", root["sh"]) or
                (expected_hash is not None and root["sh"] != expected_hash)):
            return None
        k = root["K"]
        stops = root["s"]
        codes = [row[0] for row in stops]
        if (not isinstance(stops, list) or
                any(not isinstance(row, list) or len(row) != 4 or
                    type(row[0]) is not int or not 1000 <= row[0] <= 99999
                    for row in stops) or len(codes) != len(set(codes))):
            return None
        known = {}
        if encoding in ("global_pairs", "global_base64", "global_hex"):
            field = "i" if encoding == "global_pairs" else "b"
            for row in root[field]:
                if (not isinstance(row, list) or len(row) != 2 or
                        type(row[0]) is not int or row[0] not in codes or
                        row[0] in known):
                    return None
                code, encoded = row
                if encoding == "global_pairs":
                    values = encoded
                else:
                    width = (k + 7) // 8
                    if not isinstance(encoded, str):
                        return None
                    raw = (base64.b64decode(encoded, validate=True)
                           if encoding == "global_base64" else bytes.fromhex(encoded))
                    if len(raw) != width or (int.from_bytes(raw, "little") >> k):
                        return None
                    canonical = (base64.b64encode(raw).decode("ascii")
                                 if encoding == "global_base64" else raw.hex())
                    if encoded != canonical:
                        return None
                    values = [n for n in range(k)
                              if int.from_bytes(raw, "little") & (1 << n)]
                known[code] = values
            if list(known) != sorted(known):
                return None
        else:
            aligned = root["i"]
            if len(aligned) != len(codes):
                return None
            table = root.get("q") if encoding == "global_sets" else None
            if encoding == "global_sets" and (
                    not isinstance(table, list) or
                    any(not isinstance(row, list) for row in table) or
                    table != [list(row) for row in
                              sorted({tuple(row) for row in table})]):
                return None
            for code, value in zip(codes, aligned):
                if value is None:
                    continue
                if encoding == "global_parallel":
                    values = value
                elif encoding == "global_sets":
                    if type(value) is not int or not 0 <= value < len(table):
                        return None
                    values = table[value]
                elif encoding == "global_base36":
                    if (not isinstance(value, str) or len(value) % 2 or
                            any(ch not in ALPHABET for ch in value)):
                        return None
                    values = [ALPHABET.index(value[n]) * 36 +
                              ALPHABET.index(value[n + 1])
                              for n in range(0, len(value), 2)]
                else:
                    return None
                known[code] = values
        for values in known.values():
            if (not isinstance(values, list) or not values or
                    any(type(n) is not int or not 0 <= n < k for n in values)
                    or values != sorted(set(values))):
                return None
        partial = root["p"]
        if (not isinstance(partial, list) or
                any(type(code) is not int or code not in known for code in partial)
                or partial != sorted(set(partial))):
            return None
        return {code: ("partial" if code in partial else "complete", set(values))
                for code, values in known.items()}
    except (KeyError, IndexError, TypeError, ValueError, base64.binascii.Error):
        return None


def object_counts(value):
    """JSON parser allocations, including unchanged legacy s rows."""
    count = Counter()
    def visit(obj):
        if isinstance(obj, dict):
            count["dictionaries"] += 1
            count["entries"] += len(obj)
            for key, value in obj.items():
                count["strings"] += 1
                visit(value)
        elif isinstance(obj, list):
            count["arrays"] += 1
            for value in obj:
                visit(value)
        elif isinstance(obj, str):
            count["strings"] += 1
        elif type(obj) is int:
            count["numbers"] += 1
        elif obj is None:
            count["nulls"] += 1
    visit(value)
    return dict(count)


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
    global_keys = sorted({key for _, (_, values) in data.items() for key in values})
    numbering = {key: n for n, key in enumerate(global_keys)}
    global_table = [[rid, direction] for rid, direction in global_keys]
    global_table_bytes = len(json.dumps(global_table, ensure_ascii=False,
                                        separators=(",", ":")).encode("utf-8"))
    sizes = defaultdict(list)
    worst = defaultdict(list)
    global_sizes = defaultdict(list)
    global_worst = defaultdict(list)
    global_decoded = {name: {} for name in GLOBAL_ENCODINGS}
    global_roundtrip = Counter()
    worst_objects = defaultdict(dict)
    set_counts = []
    per_tile = []
    for cell, members in membership.items():
        measured = payloads("2026-11-18", members, data)
        bodies = global_payloads("2026-11-18", members, data, numbering)
        set_counts.append(len(bodies["global_sets"]["q"]))
        for name, body in bodies.items():
            wire = json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            size = len(wire)
            global_sizes[name].append(size)
            global_worst[name].append((size, cell, len(members)))
            if size >= max((v[0] for v in worst_objects[name].values()), default=0):
                worst_objects[name] = {str(cell): (size, object_counts(body))}
            decoded = decode_global(json.loads(wire), name, "0" * 64)
            if decoded is None:
                global_roundtrip[name + "_failed_tiles"] += 1
                continue
            global_roundtrip[name + "_passed_tiles"] += 1
            for stop in members:
                state, value = data[stop.code]
                expected = None if state == "unknown" else (
                    state, {numbering[key] for key in value})
                if decoded.get(stop.code) != expected:
                    global_roundtrip[name + "_failed_rows"] += 1
                else:
                    global_roundtrip[name + "_passed_rows"] += 1
                if stop.code in global_decoded[name] and (
                        global_decoded[name][stop.code] !=
                        decoded.get(stop.code, ("unknown", set()))):
                    global_roundtrip[name + "_cross_tile_conflicts"] += 1
                global_decoded[name][stop.code] = decoded.get(
                    stop.code, ("unknown", set()))
        per_tile.append([*cell, len(members), *(measured[name] for name in
                         ("legacy", "naive", "index", "bitset")),
                         *(len(json.dumps(bodies[name], ensure_ascii=False,
                                         separators=(",", ":")).encode("utf-8"))
                           for name in GLOBAL_ENCODINGS)])
        for name, size in measured.items():
            sizes[name].append(size)
            worst[name].append((size, cell, len(members)))
    probes = Counter()
    global_probe_failures = Counter()
    numbered_source = {code: (state, {numbering[key] for key in values})
                       for code, (state, values) in data.items()}
    worst_cell = max(global_worst["global_base36"])[1]
    worst_members = membership[worst_cell]
    base_size = max(global_sizes["global_base36"])
    # Duplicate the longest name and richest key set as a deliberately
    # conservative synthetic growth estimate; no raw row is printed.
    exemplar = max(worst_members, key=lambda s: (
        len(s.name.encode("utf-8")) + 2 * len(data[s.code][1]), s.code))
    grown_members = list(worst_members)
    grown_data = dict(data)
    additional_stops = 0
    while additional_stops < 100:
        code = 90000 + additional_stops
        grown_members.append(tiles.Stop(code, exemplar.lat, exemplar.lon, exemplar.name))
        grown_data[code] = data[exemplar.code]
        grown_size = len(json.dumps(
            global_payloads("2026-11-18", grown_members, grown_data, numbering)[
                "global_base36"], ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
        if grown_size > 4096:
            break
        additional_stops += 1
    expanded_numbering = dict(numbering)
    expanded_numbering[("synthetic-new-route", 0)] = len(numbering)
    extra_data = {code: (state, values | {("synthetic-new-route", 0)}
                         if state != "unknown" else values)
                  for code, (state, values) in data.items()}
    extra_key_size = len(json.dumps(
        global_payloads("2026-11-18", worst_members, extra_data, expanded_numbering)[
            "global_base36"], ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
    examples = []
    if samples:
        for (ty, tx), members in membership.items():
            lo_lat, lo_lon = ty * 1000, tx * 1000
            for lat, lon in ((lo_lat + 500, lo_lon + 500),
                             (lo_lat, lo_lon), (lo_lat + 999, lo_lon),
                             (lo_lat, lo_lon + 999), (lo_lat + 999, lo_lon + 999)):
                reference, current, first15 = coverage(selected, members, data, lat, lon)
                expected = select(members, numbered_source, lat, lon)
                for name in GLOBAL_ENCODINGS:
                    if select(members, global_decoded[name], lat, lon) != expected:
                        global_probe_failures[name] += 1
                    else:
                        global_roundtrip[name + "_passed_probes"] += 1
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
        "global_table_entries": len(global_table), "global_table_bytes": global_table_bytes,
        "global_set_counts": {"max": max(set_counts), "median": statistics.median(set_counts),
                              "p95": percentile(set_counts)},
        "global_roundtrip": dict(global_roundtrip),
        "global_probe_failures": dict(global_probe_failures),
        "global_worst_objects": dict(worst_objects),
        "global_growth_base36": {
            "worst_tile": list(worst_cell), "base_bytes": base_size,
            "added_longest_richest_stops_that_fit": additional_stops,
            "first_stop_that_overflows_bytes": grown_size,
            "one_new_key_on_every_known_stop_bytes": extra_key_size,
            "one_new_key_on_every_known_stop_delta": extra_key_size - base_size,
            "exemplar_name_utf8_bytes": len(exemplar.name.encode("utf-8")),
            "exemplar_key_count": len(data[exemplar.code][1])},
        "per_tile_columns": ["ty", "tx", "stops", "legacy", "naive", "index", "bitset",
                             *GLOBAL_ENCODINGS],
        "per_tile": per_tile,
        "sizes": {name: {"max": max(values), "p95": percentile(values),
                         "median": statistics.median(values),
                         "overflow": sum(n > 4096 for n in values),
                         "worst": sorted(worst[name], reverse=True)[:10]}
                  for name, values in sizes.items()},
        "global_sizes": {name: {"max": max(values), "p95": percentile(values),
                               "median": statistics.median(values),
                               "overflow": sum(n > 4096 for n in values),
                               "headroom": 4096 - max(values),
                               "worst": sorted(global_worst[name], reverse=True)[:10]}
                         for name, values in global_sizes.items()},
        "probes": dict(probes), "first15_examples": examples,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("zip", help="local GTFS zip")
    parser.add_argument("--skip-probes", action="store_true", help="skip coverage probes")
    args = parser.parse_args()
    print(json.dumps(analyse(args.zip, not args.skip_probes), indent=2, sort_keys=True))
