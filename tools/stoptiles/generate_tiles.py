#!/usr/bin/env python3
"""Generate the static stop tiles for the "Departures near me" feature.

Usage:
    generate_tiles.py INPUT OUTDIR [--etag ETAG] [--previous-meta PATH]
                      [--static DIR] [--date YYYY-MM-DD]

INPUT is a GTFS zip (its ``stops.txt`` is used) or a path to a ``stops.txt``.
OUTDIR receives ``t/<ty>/<tx>.json`` tiles and ``meta.json``. The script uses
only the Python 3 standard library and never touches the network.

Tile contract v1
----------------
* Coordinates are integers in 1e-5 degrees ("E5"), rounded half up from the
  GTFS decimal strings: ``floor(value * 100000 + 0.5)``. The arithmetic is done
  with ``decimal`` so float error can never shift a value.
* Tile id: round to E5 first, then floor division (toward negative infinity):
  ``ty = floorDiv(latE5, 1000)``, ``tx = floorDiv(lonE5, 1000)``. A cell covers
  ``[ty*1000, ty*1000+999]`` in latE5 (same for lon).
* Tile body (compact UTF-8 JSON, ``ensure_ascii=False``):
  ``{"v":1,"g":"YYYY-MM-DD","s":[[stopCode,latE5,lonE5,"Name"],...]}`` with
  ``s`` sorted by stopCode. ``Name`` is the raw GTFS ``stop_name``.
* Membership: a stop is in a tile if ``ty*1000 - bLat <= latE5 <= ty*1000 + 999
  + bLat`` and the same for lon with bLon (inclusive). Buffer step k = 1..7 is
  k * 400 m (``bLat = k*360``, ``bLon = k*496``). Steps are tried from k = 1
  and widened one at a time until the tile has at least MIN_STOPS stops. If
  k = 7 is still short, the 3000 m cap (``bLat = 2698``, ``bLon = 3719``) is
  used regardless of count.
* MIN_STOPS = max(3 * NEARBY_COUNT, 10). NEARBY_COUNT is 5, so it is 15.
  Changing NEARBY_COUNT requires changing the minimum, and bumping
  GENERATOR_VERSION.
* Coverage: every cell whose rectangle lies within the cap buffer of at least
  one stop gets a file (even if ``s`` is empty). Tiles are at most 4096 bytes.
* ``meta.json``: ``{"v":1,"g":..,"gv":GENERATOR_VERSION,"n":stopCount,
  "h":sha256,"e":etag,"attribution":..}``. ``h`` is the sha256 of the sorted,
  filtered ``[stopCode, latE5, lonE5, rawName]`` list serialised as compact
  UTF-8 JSON, so it changes only when stop data changes. ``g`` is the
  generation date (UTC) unless ``--date`` is given.

Defensive filtering of stops.txt rows (each rule prints a skip count):
* ``location_type``: skip rows where location_type is set and not 0.
* ``stop_code``: skip rows with a missing or non-numeric stop_code.
* ``stop_code_range``: skip stop_code outside 1000..99999.
* ``coordinates``: skip missing, unparseable or out-of-range coordinates
  (lat -90..90, lon -180..180).
A duplicate stop_code among the remaining rows fails the run. platform_code,
zone_id and stop_desc are ignored. The run also fails if no stops remain or any
tile exceeds 4096 bytes.
"""

import argparse
import csv
import datetime
import hashlib
import io
import json
import os
import re
import shutil
import statistics
import sys
import zipfile
from collections import namedtuple
from decimal import Context, Decimal, Inexact, ROUND_FLOOR

GENERATOR_VERSION = 1
TILE_FORMAT_VERSION = 1
TILE_SIZE_E5 = 1000
MAX_TILE_BYTES = 4096
NEARBY_COUNT = 5
MIN_STOPS = max(3 * NEARBY_COUNT, 10)
STEP_COUNT = 7
STEP_LAT_E5 = 360  # 400 m of latitude
STEP_LON_E5 = 496  # 400 m of longitude at Christchurch's latitude
CAP_LAT_E5 = 2698  # 3000 m
CAP_LON_E5 = 3719  # 3000 m
MIN_STOP_CODE = 1000
MAX_STOP_CODE = 99999
LON_SCALE_NUM = 725  # watch distance approximation: dLon * 725 / 1000
LON_SCALE_DEN = 1000
ATTRIBUTION = (
    "Stop data from Environment Canterbury (Metro), licensed under "
    "CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)"
)

Stop = namedtuple("Stop", ["code", "lat", "lon", "name"])

SKIP_RULES = ("location_type", "stop_code", "stop_code_range", "coordinates")

_DECIMAL_RE = re.compile(r"[+-]?(\d+\.?\d*|\.\d+)", re.ASCII)


class GeneratorError(Exception):
    """A condition that must fail the run with a clear message."""


def to_e5(text):
    """Convert a GTFS decimal-degree string to E5, rounding half up."""
    text = text.strip()
    if not _DECIMAL_RE.fullmatch(text):
        raise ValueError("not a decimal number: %r" % text)
    # Enough precision that every operation is exact; Inexact would raise.
    ctx = Context(prec=len(text) + 10, traps=[Inexact])
    scaled = ctx.add(ctx.multiply(Decimal(text), Decimal(100000)), Decimal("0.5"))
    return int(scaled.to_integral_value(rounding=ROUND_FLOOR))


def tile_id(e5):
    """Tile index for an E5 coordinate: floor division, not truncation."""
    return e5 // TILE_SIZE_E5


def _parse_int(text):
    text = text.strip()
    if text.isascii() and text.isdigit():
        return int(text)
    return None


def parse_stops(rows):
    """Filter GTFS stops rows. Returns (stops sorted by code, skip counts)."""
    skipped = {rule: 0 for rule in SKIP_RULES}
    by_code = {}
    for row in rows:
        location_type = (row.get("location_type") or "").strip()
        if location_type != "" and _parse_int(location_type) != 0:
            skipped["location_type"] += 1
            continue
        code = _parse_int(row.get("stop_code") or "")
        if code is None:
            skipped["stop_code"] += 1
            continue
        if not MIN_STOP_CODE <= code <= MAX_STOP_CODE:
            skipped["stop_code_range"] += 1
            continue
        try:
            lat = to_e5(row.get("stop_lat") or "")
            lon = to_e5(row.get("stop_lon") or "")
        except ValueError:
            skipped["coordinates"] += 1
            continue
        if abs(lat) > 9000000 or abs(lon) > 18000000:
            skipped["coordinates"] += 1
            continue
        if code in by_code:
            raise GeneratorError("duplicate stop_code %d" % code)
        by_code[code] = Stop(code, lat, lon, row.get("stop_name") or "")
    return [by_code[code] for code in sorted(by_code)], skipped


def read_stops_rows(path):
    """Read stops.txt rows from a GTFS zip or a plain stops.txt path."""
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            names = [n for n in archive.namelist() if n == "stops.txt"]
            if not names:
                raise GeneratorError("no stops.txt in %s" % path)
            data = archive.read(names[0])
    else:
        with open(path, "rb") as handle:
            data = handle.read()
    text = io.StringIO(data.decode("utf-8-sig"), newline="")
    reader = csv.DictReader(text)
    header = [name.strip() for name in (reader.fieldnames or [])]
    for column in ("stop_code", "stop_lat", "stop_lon"):
        if column not in header:
            raise GeneratorError("stops.txt has no %s column" % column)
    reader.fieldnames = header
    return list(reader)


def load_stops(path):
    return parse_stops(read_stops_rows(path))


def tile_members(candidates, ty, tx):
    """Stops for a tile, widening the buffer 400 m at a time up to the cap."""
    lat_lo = ty * TILE_SIZE_E5
    lat_hi = lat_lo + TILE_SIZE_E5 - 1
    lon_lo = tx * TILE_SIZE_E5
    lon_hi = lon_lo + TILE_SIZE_E5 - 1

    def within(b_lat, b_lon):
        return [
            s for s in candidates
            if lat_lo - b_lat <= s.lat <= lat_hi + b_lat
            and lon_lo - b_lon <= s.lon <= lon_hi + b_lon
        ]

    for k in range(1, STEP_COUNT + 1):
        members = within(k * STEP_LAT_E5, k * STEP_LON_E5)
        if len(members) >= MIN_STOPS:
            return members
    return within(CAP_LAT_E5, CAP_LON_E5)


def covered_cells(stops):
    """Every (ty, tx) whose rectangle is within the cap buffer of a stop."""
    cells = set()
    for s in stops:
        for ty in range(tile_id(s.lat - CAP_LAT_E5), tile_id(s.lat + CAP_LAT_E5) + 1):
            for tx in range(tile_id(s.lon - CAP_LON_E5), tile_id(s.lon + CAP_LON_E5) + 1):
                cells.add((ty, tx))
    return cells


def build_tiles(stops):
    """Return {(ty, tx): [Stop, ...]} for every covered cell."""
    tiles = {}
    for ty, tx in sorted(covered_cells(stops)):
        lat_lo = ty * TILE_SIZE_E5 - CAP_LAT_E5
        lat_hi = ty * TILE_SIZE_E5 + TILE_SIZE_E5 - 1 + CAP_LAT_E5
        lon_lo = tx * TILE_SIZE_E5 - CAP_LON_E5
        lon_hi = tx * TILE_SIZE_E5 + TILE_SIZE_E5 - 1 + CAP_LON_E5
        candidates = [
            s for s in stops
            if lat_lo <= s.lat <= lat_hi and lon_lo <= s.lon <= lon_hi
        ]
        tiles[(ty, tx)] = sorted(tile_members(candidates, ty, tx))
    return tiles


def _dumps(obj):
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":"))


def encode_tile(date, stops):
    body = {
        "v": TILE_FORMAT_VERSION,
        "g": date,
        "s": [[s.code, s.lat, s.lon, s.name] for s in sorted(stops)],
    }
    return _dumps(body).encode("utf-8")


def stops_hash(stops):
    payload = _dumps([[s.code, s.lat, s.lon, s.name] for s in sorted(stops)])
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def build_meta(date, stops, etag):
    return {
        "v": TILE_FORMAT_VERSION,
        "g": date,
        "gv": GENERATOR_VERSION,
        "n": len(stops),
        "h": stops_hash(stops),
        "e": etag or "",
        "attribution": ATTRIBUTION,
    }


def nearest(stops, lat, lon, count=NEARBY_COUNT):
    """Nearest stops using the watch's distance approximation.

    d2 = (dLat * 1000)^2 + (dLon * 725)^2 is the squared distance with dLon
    scaled by 725/1000, multiplied by 1e6 so that it is exact in integers.
    Ties are broken by the lower stop code.
    """
    def key(s):
        d_lat = (s.lat - lat) * LON_SCALE_DEN
        d_lon = (s.lon - lon) * LON_SCALE_NUM
        return (d_lat * d_lat + d_lon * d_lon, s.code)

    return sorted(stops, key=key)[:count]


def write_output(outdir, tiles, meta, date, static_dir=None):
    """Encode every tile (failing on size) and then write the output tree."""
    encoded = {}
    for (ty, tx), members in tiles.items():
        data = encode_tile(date, members)
        if len(data) > MAX_TILE_BYTES:
            raise GeneratorError(
                "tile %d/%d is %d bytes, over the %d byte limit"
                % (ty, tx, len(data), MAX_TILE_BYTES))
        encoded[(ty, tx)] = data

    tile_root = os.path.join(outdir, "t")
    if os.path.isdir(tile_root):
        shutil.rmtree(tile_root)  # drop stale tiles from a previous run
    os.makedirs(outdir, exist_ok=True)
    if static_dir:
        shutil.copytree(static_dir, outdir, dirs_exist_ok=True)
    for (ty, tx), data in encoded.items():
        directory = os.path.join(tile_root, str(ty))
        os.makedirs(directory, exist_ok=True)
        with open(os.path.join(directory, "%d.json" % tx), "wb") as handle:
            handle.write(data)
    with open(os.path.join(outdir, "meta.json"), "wb") as handle:
        handle.write(_dumps(meta).encode("utf-8"))
    return [len(d) for d in encoded.values()]


def _read_previous(path):
    """Read a previous meta.json. Returns (meta or None, error or None)."""
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle), None
    except (OSError, ValueError) as error:
        return None, error


def _print_previous(old, error, meta, out):
    if old is None:
        print("previous meta: unreadable (%s)" % error, file=out)
        return
    print("previous meta: n=%s h=%s gv=%s" % (old.get("n"), old.get("h"), old.get("gv")),
          file=out)
    print("new meta:      n=%s h=%s gv=%s" % (meta["n"], meta["h"], meta["gv"]), file=out)


def generate(input_path, outdir, etag="", date=None, previous_meta=None,
             static_dir=None, out=None):
    out = out or sys.stdout
    date = date or datetime.datetime.now(datetime.timezone.utc).date().isoformat()
    stops, skipped = load_stops(input_path)
    for rule in SKIP_RULES:
        print("skipped (%s): %d" % (rule, skipped[rule]), file=out)
    if not stops:
        raise GeneratorError("no stops left after filtering")

    tiles = build_tiles(stops)
    meta = build_meta(date, stops, etag)
    # Read before write_output, which may replace the file (OUTDIR/meta.json).
    previous = _read_previous(previous_meta) if previous_meta else (None, None)
    sizes = write_output(outdir, tiles, meta, date, static_dir)

    print("stops: %d" % len(stops), file=out)
    print("tiles: %d" % len(tiles), file=out)
    print("total bytes: %d" % sum(sizes), file=out)
    print("median tile bytes: %d" % statistics.median(sizes), file=out)
    print("max tile bytes: %d" % max(sizes), file=out)
    print("max stops per tile: %d" % max(len(m) for m in tiles.values()), file=out)
    print("hash: %s" % meta["h"], file=out)
    print("gv: %d" % meta["gv"], file=out)
    if previous_meta:
        _print_previous(previous[0], previous[1], meta, out)
    return meta


def main(argv=None):
    parser = argparse.ArgumentParser(description="Generate stop tiles from GTFS stops.")
    parser.add_argument("input", help="GTFS zip or stops.txt path")
    parser.add_argument("outdir", help="output directory (for example site/)")
    parser.add_argument("--etag", default="", help="ETag of the gtfs.zip used")
    parser.add_argument("--previous-meta", help="previous meta.json to compare")
    parser.add_argument("--static", help="directory of static files to copy into outdir")
    parser.add_argument("--date", help="generation date, YYYY-MM-DD (default: today, UTC)")
    args = parser.parse_args(argv)
    if args.date:
        try:
            if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", args.date, re.ASCII):
                raise ValueError(args.date)
            datetime.date.fromisoformat(args.date)
        except ValueError:
            parser.error("--date must be YYYY-MM-DD")
    try:
        generate(args.input, args.outdir, etag=args.etag, date=args.date,
                 previous_meta=args.previous_meta, static_dir=args.static)
    except (GeneratorError, OSError, zipfile.BadZipFile, UnicodeDecodeError, csv.Error) as error:
        print("error: %s" % error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
