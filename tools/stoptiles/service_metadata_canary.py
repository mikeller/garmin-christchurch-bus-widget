#!/usr/bin/env python3
"""Advisory canary for the v2 service-metadata opt-in (standard library only).

Runs the generator with ``--service-metadata`` against an already-downloaded
``gtfs.zip`` into a caller-supplied scratch directory, and reports whether the
feed currently satisfies the preconditions for setting
``STOP_TILES_SERVICE_METADATA=true``: a usable global key set and every tile
still within the 4096 byte limit. This is diagnostic evidence for a human, not
a gate: it never raises past ``main()`` and always exits 0. It imports
``generate_tiles``/``service_metadata`` directly rather than shelling out to
the generator CLI, and never writes to the real ``site`` output tree.

Usage:
    service_metadata_canary.py GTFS_ZIP SCRATCH_DIR [--date YYYY-MM-DD]

On success, prints the tile count, the global key count K, the largest tile
size in bytes, and the headroom (``MAX_TILE_BYTES`` minus the largest tile
size) in bytes, then a line ``PRECONDITIONS: PASS``. On a caught
``GeneratorError`` (or another error the real generator CLI itself treats as a
run failure), it prints the error message and ``PRECONDITIONS: FAIL`` instead.
"""

import argparse
import csv
import io
import re
import sys
import zipfile

from generate_tiles import MAX_TILE_BYTES, generate
from generator_error import GeneratorError

_TILES_RE = re.compile(r"^tiles: (\d+)$")
_MAX_TILE_BYTES_RE = re.compile(r"^max tile bytes: (\d+)$")

# The same set generate_tiles.main() treats as a reported run failure rather
# than an uncaught crash, so this advisory check never blows up the build job.
GENERATOR_FAILURES = (GeneratorError, OSError, zipfile.BadZipFile,
                      UnicodeDecodeError, csv.Error)


def _parse_metric(captured, pattern, label):
    for line in captured.splitlines():
        match = pattern.match(line)
        if match:
            return int(match.group(1))
    raise GeneratorError("generator output has no %r line" % label)


def check(gtfs_path, scratch_dir, date=None):
    """Run the generator with service metadata into a scratch directory.

    Returns a dict with ``tiles``, ``k``, ``max_tile_bytes`` and ``headroom``
    on success. Raises one of GENERATOR_FAILURES on a precondition failure.
    Never touches ``site``: the caller is responsible for passing a scratch
    directory that is not the real published output tree.
    """
    captured = io.StringIO()
    meta = generate(gtfs_path, scratch_dir, date=date, out=captured,
                    service_metadata_enabled=True)
    output = captured.getvalue()
    tiles = _parse_metric(output, _TILES_RE, "tiles")
    max_tile_bytes = _parse_metric(output, _MAX_TILE_BYTES_RE, "max tile bytes")
    return {
        "tiles": tiles,
        "k": meta["K"],
        "max_tile_bytes": max_tile_bytes,
        "headroom": MAX_TILE_BYTES - max_tile_bytes,
    }


def report(gtfs_path, scratch_dir, date=None, out=None):
    """Print the advisory verdict. Always succeeds; never raises."""
    out = out if out is not None else sys.stdout
    try:
        result = check(gtfs_path, scratch_dir, date=date)
    except GENERATOR_FAILURES as error:
        print("error: %s" % error, file=out)
        print("PRECONDITIONS: FAIL", file=out)
        return
    print("tiles: %d" % result["tiles"], file=out)
    print("K: %d" % result["k"], file=out)
    print("max tile bytes: %d" % result["max_tile_bytes"], file=out)
    print("headroom bytes: %d" % result["headroom"], file=out)
    print("PRECONDITIONS: PASS", file=out)


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("gtfs", help="path to an already-downloaded gtfs.zip")
    parser.add_argument("scratch_dir",
                        help="scratch output directory; never the real site/ tree")
    parser.add_argument("--date", help="generation date, YYYY-MM-DD (default: today, UTC)")
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    report(args.gtfs, args.scratch_dir, date=args.date)
    return 0


if __name__ == "__main__":
    sys.exit(main())
