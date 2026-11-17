"""Offline GTFS join for optional digest-bound, globally numbered service keys."""

import csv
import datetime
import hashlib
import io
import json
import re
import zipfile
from collections import defaultdict

from generate_tiles import _dumps, _parse_int
from generator_error import GeneratorError

ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz"
REQUIRED = ("stops", "routes", "trips", "stop_times", "calendar", "calendar_dates",
            "feed_info")


def _rows(archive, name):
    try:
        with archive.open(name + ".txt") as stream:
            reader = csv.DictReader(io.TextIOWrapper(
                stream, encoding="utf-8-sig", newline=""))
            if not reader.fieldnames:
                raise GeneratorError("%s.txt has no header" % name)
            yield from reader
    except KeyError:
        raise GeneratorError("--service-metadata requires %s.txt" % name) from None


def _date(text):
    if not isinstance(text, str) or not re.fullmatch(r"[0-9]{8}", text):
        raise GeneratorError("invalid GTFS date %r" % text)
    try:
        return datetime.datetime.strptime(text, "%Y%m%d").date()
    except ValueError:
        raise GeneratorError("invalid GTFS date %r" % text) from None


def _unique(rows, field):
    result = {}
    for row in rows:
        value = row.get(field)
        if not value or value in result:
            raise GeneratorError("missing or duplicate %s in GTFS" % field)
        result[value] = row
    return result


def _calendar(archive, generation):
    info = list(_rows(archive, "feed_info"))
    if len(info) != 1:
        raise GeneratorError("feed_info.txt must declare one horizon")
    start = _date(info[0].get("feed_start_date"))
    end = _date(info[0].get("feed_end_date"))
    if end < start or not start <= generation <= end:
        raise GeneratorError(
            "GTFS feed horizon is invalid or does not include the generation date")
    if (end - start).days > 3660:
        raise GeneratorError("GTFS feed horizon exceeds ten years")
    calendar = _unique(_rows(archive, "calendar"), "service_id")
    exceptions = defaultdict(dict)
    for row in _rows(archive, "calendar_dates"):
        sid = row.get("service_id")
        day = _date(row.get("date"))
        kind = row.get("exception_type")
        if (not sid or kind not in ("1", "2") or day < start or day > end
                or day in exceptions[sid]):
            raise GeneratorError("invalid calendar_dates entry")
        exceptions[sid][day] = kind
    active = set()
    for sid in sorted(set(calendar) | set(exceptions)):
        row = calendar.get(sid)
        if row is not None:
            first, last = _date(row.get("start_date")), _date(row.get("end_date"))
            flags = [row.get(day) for day in (
                "monday", "tuesday", "wednesday", "thursday", "friday",
                "saturday", "sunday")]
            if first > last or any(flag not in ("0", "1") for flag in flags):
                raise GeneratorError("invalid calendar entry for service_id %s" % sid)
        for offset in range((end - start).days + 1):
            day = start + datetime.timedelta(days=offset)
            scheduled = row is not None and first <= day <= last and flags[day.weekday()] == "1"
            effective = exceptions[sid].get(day, "1" if scheduled else "2") == "1"
            if effective:
                active.add(sid)
                break
    return start.isoformat(), end.isoformat(), active, set(calendar) | set(exceptions)


def _base36(n):
    return ALPHABET[n // 36] + ALPHABET[n % 36]


def build(path, stops, generation, existing_stops_h):
    """Return (states by public code, global keys, sh); no feed rows leave this module."""
    if not zipfile.is_zipfile(path):
        raise GeneratorError("--service-metadata requires a GTFS zip, not stops.txt")
    with zipfile.ZipFile(path) as archive:
        missing = [name for name in REQUIRED if name + ".txt" not in archive.namelist()]
        if missing:
            raise GeneratorError("--service-metadata requires %s.txt" % missing[0])
        start, end, active, defined = _calendar(archive, datetime.date.fromisoformat(generation))
        source = _unique(_rows(archive, "stops"), "stop_id")
        routes = _unique(_rows(archive, "routes"), "route_id")
        trips = _unique(_rows(archive, "trips"), "trip_id")
        for trip in trips.values():
            if trip.get("service_id") not in defined:
                raise GeneratorError("trip references undefined service_id")
            if trip.get("route_id") not in routes:
                raise GeneratorError("trip references missing route_id")
            if trip.get("direction_id") not in ("0", "1"):
                raise GeneratorError("trip has invalid direction_id")
        by_code = defaultdict(list)
        for sid, row in source.items():
            code = _parse_int(row.get("stop_code") or "")
            if code is not None:
                by_code[code].append(sid)
        keys = defaultdict(set)
        broken = set()
        for row in _rows(archive, "stop_times"):
            sid = row.get("stop_id")
            if sid not in source:
                # This visit cannot be attributed to a public stop.
                raise GeneratorError("stop_times references missing stop_id")
            trip = trips.get(row.get("trip_id"))
            if trip is None:
                broken.add(sid)
                continue
            if trip["service_id"] not in active:
                continue
            pickup = row.get("pickup_type", "")
            if pickup not in ("", "0", "1", "2", "3"):
                broken.add(sid)
            elif pickup in ("2", "3"):
                # Boardable only by arrangement: not an unrestricted key, but
                # the stop's key set is then incomplete, so never suppress it.
                broken.add(sid)
            elif pickup in ("", "0"):
                keys[sid].add((trip["route_id"], int(trip["direction_id"])))
    states = {}
    for stop in stops:
        ids = by_code[stop.code]
        if len(ids) != 1 or not keys[ids[0]]:
            states[stop.code] = ("unknown", set())
        else:
            states[stop.code] = ("partial" if ids[0] in broken else "complete", keys[ids[0]])
    global_keys = sorted({key for _, values in states.values() for key in values},
                         key=lambda key: (key[0].encode("utf-8"), key[1]))
    if not global_keys or len(global_keys) > 1296:
        raise GeneratorError("service metadata requires 1..1296 usable global keys")
    payload = [2, generation, existing_stops_h, start, end,
               [[rid, direction] for rid, direction in global_keys],
               [[code, state, [[rid, direction] for rid, direction in sorted(
                   values, key=lambda key: (key[0].encode("utf-8"), key[1]))]]
                for code, (state, values) in sorted(states.items())]]
    digest = hashlib.sha256(_dumps(payload).encode("utf-8")).hexdigest()
    return states, global_keys, digest


def encode(stops, states, numbering, digest):
    """Aligned two-digit base36 strings, with null for unknown stop rows."""
    indices = []
    partial = []
    for stop in stops:
        state, keys = states[stop.code]
        indices.append(None if state == "unknown" else
                       "".join(_base36(n) for n in sorted(numbering[key] for key in keys)))
        if state == "partial":
            partial.append(stop.code)
    return {"m": 2, "sh": digest, "K": len(numbering), "i": indices, "p": partial}
