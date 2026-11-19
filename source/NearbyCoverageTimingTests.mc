import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// A basic, simulator-only timing sanity check for the coverage-selection
// performance fix (see tools/stoptiles/NEARBY_VALIDATION.md). Unit tests
// cannot assert against the Connect IQ watchdog directly, so this only logs
// elapsed `System.getTimer()` milliseconds for a worst-case-shaped synthetic
// tile against the host simulator's CPU; it is evidence, not a timed
// pass/fail bound, and does not substitute for real-device timing.
(:debug, :nearby)
class NearbyCoverageTimingFixture {
    // NearbyServiceContext.MAX_STOPS (292) is the array-size cap, but
    // NearbyServiceContext.MAX_BYTES (4096) caps the realistic row count
    // well below that for any non-trivial name length (the real 18 Nov 2026
    // GTFS snapshot's largest tile was 56 stops at 3,812 bytes; see
    // NEARBY_VALIDATION.md). 160 one-character-name rows mirrors the
    // existing "bounded tile full scan" coverage test and stays usable.
    //
    // Rows alternate between two service keys so almost every candidate
    // after the first couple is "covered" and rejected: the scan must
    // examine nearly every row without ever reaching the n=5 target,
    // exercising the full scan x row-search loop rather than stopping early.
    static function worstCaseTile() as Dictionary {
        var rows = [] as Array;
        var keys = [] as Array;
        for (var i = 0; i < 160; i++) {
            rows.add([1001 + i, i, i + 1, "S"]);
            keys.add(i % 2 == 0 ? "00" : "01");
        }
        return {"v" => 1, "g" => "2026-11-18", "s" => rows,
            "m" => 2, "sh" => NearbyServiceTestData.DIGEST,
            "K" => 60, "i" => keys, "p" => []} as Dictionary;
    }
}

(:test, :nearby)
function testNearbyCoverageWorstCaseTiming(logger as Logger) as Boolean {
    var tile = NearbyCoverageTimingFixture.worstCaseTile();
    Test.assertMessage(NearbyServiceContext.usable(tile), "worst-case tile is usable");
    var context = NearbyServiceContext.context(tile, true);
    var favourites = [] as Array<Number>;
    for (var i = 0; i < 16; i++) {
        // Favourites scattered through the tile (still within its 160
        // rows), not just the nearest rows, so the favourite-admission
        // pointer walks its full sorted list.
        favourites.add(1001 + i * 10);
    }
    var rows = tile["s"] as Array;
    var started = System.getTimer();
    var selected = NearbyCoverageSelection.select([context], 80, 80, favourites, 5);
    var elapsedMs = System.getTimer() - started;
    System.println("TIMING coverage-select rows=" + rows.size() +
        " favourites=" + favourites.size() + " elapsedMs=" + elapsedMs);
    Test.assertMessage((selected[0] as Array).size() <= 5, "result bounded by n");
    return true;
}
