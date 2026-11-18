#!/usr/bin/env python3
"""Check the known glance call graph against monkeyc's device debug XML.

Usage: python3 tools/check_glance_scope.py fr945.prg.debug.xml \
    instinct2.prg.debug.xml fr55.prg.debug.xml

This checks symbols and resource scope after annotation exclusion; it cannot
prove dynamic call paths, runtime API behaviour, or heap peaks.
"""

import sys
import xml.etree.ElementTree as ET
from pathlib import Path


SHARED = {
    "ChristchurchBusApp": ("initialize", "getGlanceView"),
    "ChristchurchBusAppProperties": ("loadStops", "getStopsProperty",
                                     "nearbyEnabled", "getStopResetTimeMin"),
    "ChristchurchBusDataCache": ("getLastStop", "tryGetCachedData"),
    "ChristchurchBusGlanceView": ("initialize", "onLayout", "onUpdate"),
    "StoredBusData": ("validStop", "validLastStop", "validDeparture"),
    "Utils": ("parseIsoDate", "log", "dateToIsoString"),
    "Constants": ("LAST_STOP_INDEX_NAME", "NO_INFORMATION_STRING",
                  "VERTICAL_SPACE"),
}
NEARBY = {
    "ChristchurchBusApp": ("selectFavouriteForGlance", "cachedNearbyTitleStop"),
    "NearbyGlanceSelection": ("favourite", "select"),
    "ChristchurchBusDataCache": ("getLastFavourite", "restoreLastFavourite",
                                 "getNearbyStop"),
    "NearbyFavouriteMemory": ("restore",),
    "NearbyGlanceTitle": ("isBlank", "title", "trim"),
    "NearbyGlanceAge": ("label",),
    "StoredBusData": ("validNearbyResult",),
}
STRINGS = ("AppName", "NoInformation", "StopCodeFallback",
           "NoStops", "NoBuses", "UnknownError")
FUNCTIONS = {
    "ChristchurchBusApp", "ChristchurchBusAppProperties",
    "ChristchurchBusDataCache", "ChristchurchBusGlanceView",
    "NearbyGlanceSelection", "NearbyGlanceTitle", "NearbyGlanceAge",
    "NearbyFavouriteMemory", "StoredBusData", "Utils",
}


def check(path):
    root = ET.parse(path).getroot()
    annotations = {
        (entry.get("class"), entry.get("symbol"))
        for entry in root.find("annotations")
        if entry.get("annotation") == "glance"
    }
    resources = {
        entry.get("symbol")
        for entry in root.find("annotations")
        if entry.get("annotation") == "glance"
        and entry.get("module") == "globals/GlanceRez"
        and entry.get("class") == "Strings"
    }
    functions = {
        (entry.get("parent"), entry.get("name"))
        for entry in root.find("functions")
    }
    # The noNearby build omits NearbyGlanceSelection entirely. Do not infer this
    # from a filename or configuration outside the compiled artefact.
    nearby = ("NearbyGlanceSelection", "select") in functions
    expected = dict(SHARED)
    if nearby:
        for owner, symbols in NEARBY.items():
            expected[owner] = expected.get(owner, ()) + symbols
    errors = []
    for owner, symbols in expected.items():
        for symbol in symbols:
            if (owner, symbol) not in annotations:
                errors.append(f"{owner}.{symbol} lacks :glance")
            if owner in FUNCTIONS and symbol not in ("KEY", "trim"):
                if not any(parent == owner and
                           (name == symbol or symbol in name and name.startswith("<"))
                           for parent, name in functions):
                    errors.append(f"{owner}.{symbol} missing from functions")
    for symbol in STRINGS:
        if symbol not in resources:
            errors.append(f"GlanceRez.Strings.{symbol} lacks :glance")
    if not nearby:
        for owner, symbols in NEARBY.items():
            for symbol in symbols:
                if (owner, symbol) in annotations or (owner, symbol) in functions:
                    errors.append(f"{owner}.{symbol} leaks into excluded glance")
    print(f"{path}: {'nearby' if nearby else 'favourites-only'} "
          f"{'FAIL: ' + '; '.join(errors) if errors else 'scope OK'}")
    return bool(errors)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("Pass device .prg.debug.xml files")
    source = (Path(__file__).resolve().parents[1] /
              "source/ChristchurchBusAppProperties.mc").read_text()
    nearby_enabled = source.split("static function nearbyEnabled()", 1)[1].split(
        "static function favouritesBeforeNearby()", 1)[0]
    if "NearbyAvailability." in nearby_enabled:
        sys.exit("nearbyEnabled crosses from glance into widget-only NearbyAvailability")
    sys.exit(any([check(path) for path in sys.argv[1:]]))
