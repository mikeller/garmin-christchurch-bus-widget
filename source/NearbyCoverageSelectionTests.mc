import Toybox.Lang;
import Toybox.Test;

(:debug, :nearby)
class NearbyCoverageTestData {
    static function context(rows as Array, keys as Array, partial as Array) as Dictionary {
        var tile = {"v" => 1, "g" => "2026-11-18", "s" => rows,
            "m" => 2, "sh" => NearbyServiceTestData.DIGEST, "K" => 60,
            "i" => keys, "p" => partial} as Dictionary;
        return NearbyServiceContext.context(tile, true);
    }

    static function codes(contexts as Array, favourites as Array<Number>, n as Number) as String {
        return NearbyStopMathsTestData.codes(
            NearbyCoverageSelection.select(contexts, 0, 0, favourites, n)[0] as Array);
    }
}

(:test, :nearby)
function testNearbyCoverageRules(logger as Logger) as Boolean {
    var rows = [[1001, 0, 1, "A"], [1002, 0, 2, "B"],
                [1003, 0, 3, "C"], [1004, 0, 4, "D"],
                [1005, 0, 5, "E"]] as Array;
    var none = [] as Array<Number>;
    var ctx = NearbyCoverageTestData.context(rows, ["0001", "00", "01", "0102", "02"], []);
    Test.assertEqualMessage("[1001, 1004]", NearbyCoverageTestData.codes([ctx], none, 3),
        "equal, overlap and union of retained stops");
    Test.assertEqualMessage("[1001]", NearbyCoverageTestData.codes([ctx], none, 1),
        "one slot");
    ctx = NearbyCoverageTestData.context(rows, ["00", "01", "02", "03", "04"], []);
    Test.assertEqualMessage("[1001, 1002, 1003, 1004, 1005]",
        NearbyCoverageTestData.codes([ctx], none, 5), "disjoint five");
    ctx = NearbyCoverageTestData.context(rows, ["00", "0001", "01", "02", "03"], []);
    Test.assertEqualMessage("[1001, 1002, 1004]",
        NearbyCoverageTestData.codes([ctx], none, 3),
        "new key retains whole stop, not just uncovered departures");
    ctx = NearbyCoverageTestData.context(rows, ["00", "00", "01", "01", "02"], []);
    Test.assertEqualMessage("[1001, 1003, 1005]",
        NearbyCoverageTestData.codes([ctx], none, 3),
        "dropped stop does not contribute");
    ctx = NearbyCoverageTestData.context(rows, [null, "00", "00", "01", "02"], []);
    Test.assertEqualMessage("[1001, 1002, 1004]",
        NearbyCoverageTestData.codes([ctx], none, 3), "unknown never contributes");
    ctx = NearbyCoverageTestData.context(rows, ["00", "00", "00", "01", "02"], [1001]);
    Test.assertEqualMessage("[1001, 1002, 1004]",
        NearbyCoverageTestData.codes([ctx], none, 3), "partial never contributes");
    Test.assertEqualMessage("[1001, 1002, 1004, 1005]",
        NearbyCoverageTestData.codes([ctx], none, 5), "fewer than five");
    Test.assertEqualMessage("[]", NearbyCoverageTestData.codes(
        [NearbyCoverageTestData.context([] as Array, [] as Array, [] as Array)],
        none, 3), "empty tile");
    return true;
}

(:test, :nearby)
function testNearbyCoverageBeyondFifteenAndTies(logger as Logger) as Boolean {
    var rows = [] as Array;
    var keys = [] as Array;
    for (var i = 0; i < 25; i++) {
        rows.add([1001 + i, 0, i + 1, "S"]);
        keys.add(i == 19 ? "01" : "00");
    }
    var ctx = NearbyCoverageTestData.context(rows, keys, []);
    Test.assertEqualMessage("[1001, 1020]", NearbyCoverageTestData.codes([ctx],
        [] as Array<Number>, 3), "scan whole loaded tile");
    rows = [] as Array;
    keys = [] as Array;
    for (var i = 0; i < 160; i++) {
        rows.add([1001 + i, 0, i + 1, "S"]);
        keys.add(i == 159 ? "01" : "00");
    }
    ctx = NearbyCoverageTestData.context(rows, keys, []);
    Test.assertMessage(ctx["i"] != null, "large bounded tile metadata usable");
    Test.assertEqualMessage("[1001, 1160]", NearbyCoverageTestData.codes([ctx],
        [] as Array<Number>, 5), "bounded tile full scan");
    rows = [[1001, 0, 1, "A"], [1002, 0, -1, "B"], [1003, 0, 2, "C"]];
    ctx = NearbyCoverageTestData.context(rows, ["00", "00", "01"], []);
    Test.assertEqualMessage("[1001, 1003]", NearbyCoverageTestData.codes([ctx],
        [] as Array<Number>, 3), "equal distance sorts by code");
    return true;
}

(:test, :nearby)
function testNearbyCoverageFavourites(logger as Logger) as Boolean {
    var rows = [[1001, 0, 1, "F"], [1002, 0, 2, "A"],
                [1003, 0, 3, "B"], [1004, 0, 4, "C"]];
    var ctx = NearbyCoverageTestData.context(rows, ["00", "00", "01", "01"], []);
    Test.assertEqualMessage("[1003]", NearbyCoverageTestData.codes([ctx],
        [1001] as Array<Number>, 3), "closer favourite covers");
    Test.assertEqualMessage("[1001]", NearbyCoverageTestData.codes([ctx],
        [1003] as Array<Number>, 3), "closer favourite still covers later stop");
    ctx = NearbyCoverageTestData.context(rows, ["00", "01", "01", "02"], []);
    Test.assertEqualMessage("[1001, 1002, 1004]", NearbyCoverageTestData.codes([ctx],
        [1003] as Array<Number>, 3), "farther favourite does not cover");
    ctx = NearbyCoverageTestData.context(rows, ["00", "00", "01", "01"], []);
    Test.assertEqualMessage("[1001, 1003]", NearbyCoverageTestData.codes([ctx],
        [9999] as Array<Number>, 3), "out of tile favourite");
    ctx = NearbyCoverageTestData.context(rows, [null, "00", "01", "01"], []);
    Test.assertEqualMessage("[1002, 1003]", NearbyCoverageTestData.codes([ctx],
        [1001] as Array<Number>, 3), "unknown favourite");
    ctx = NearbyCoverageTestData.context(rows, ["00", "00", "01", "01"], [1001]);
    Test.assertEqualMessage("[1002, 1003]", NearbyCoverageTestData.codes([ctx],
        [1001] as Array<Number>, 3), "partial favourite");
    ctx = NearbyCoverageTestData.context(rows, ["00", "01", "02", "03"], []);
    var split = NearbyCoverageSelection.select([ctx], 0, 0,
        [1001, 1003] as Array<Number>, 3);
    Test.assertEqualMessage("[1002, 1004]",
        NearbyStopMathsTestData.codes(split[0] as Array),
        "multiple favourites do not take slots or duplicate nearby");
    Test.assertEqualMessage("[1001, 1003]",
        NearbyStopMathsTestData.codes(split[1] as Array), "favourite distances preserved");
    rows = [[1001, 0, -2, "F"], [1002, 0, 2, "A"]];
    ctx = NearbyCoverageTestData.context(rows, ["00", "00"], []);
    Test.assertEqualMessage("[1002]", NearbyCoverageTestData.codes([ctx],
        [1001] as Array<Number>, 3), "tied favourite does not pre-cover");
    return true;
}

(:test, :nearby)
function testNearbyCoverageFallback(logger as Logger) as Boolean {
    var rows = [] as Array;
    var keys = [] as Array;
    for (var i = 0; i < 40; i++) {
        rows.add([1001 + i, i % 7, (i * 13) % 19, "Stop"]);
        keys.add("00");
    }
    var ctx = NearbyCoverageTestData.context(rows, keys, []);
    var legacy = {"s" => rows, "g" => "2026-11-18"} as Dictionary;
    var favourites = [1002, 1012] as Array<Number>;
    for (var lat = -3; lat < 4; lat++) {
        for (var lon = -3; lon < 4; lon++) {
            for (var n = 1; n <= 5; n++) {
                var expected = NearbyStopMaths.nearestSplit(rows, lat, lon, favourites, n);
                var actual = NearbyCoverageSelection.select([legacy], lat, lon, favourites, n);
                Test.assertEqualMessage(NearbyStopMathsTestData.codes(expected[0] as Array),
                    NearbyStopMathsTestData.codes(actual[0] as Array), "metadata-less legacy");
                Test.assertEqualMessage(NearbyStopMathsTestData.codes(expected[1] as Array),
                    NearbyStopMathsTestData.codes(actual[1] as Array), "favourites legacy");
            }
        }
    }
    var other = NearbyCoverageTestData.context([[2001, 0, 1, "Other"]], ["00"], []);
    other["K"] = 61;
    Test.assertEqualMessage("[1001, 2001]",
        NearbyCoverageTestData.codes([ctx, other], [] as Array<Number>, 2),
        "mixed K is legacy");
    other["K"] = ctx["K"];
    other["sh"] = "1111111111111111111111111111111111111111111111111111111111111111";
    Test.assertEqualMessage("[1001, 2001]",
        NearbyCoverageTestData.codes([ctx, other], [] as Array<Number>, 2),
        "mixed digest is legacy");
    other["sh"] = ctx["sh"];
    other["g"] = "2026-11-19";
    Test.assertEqualMessage("[1001, 2001]",
        NearbyCoverageTestData.codes([ctx, other], [] as Array<Number>, 2),
        "mixed generation is legacy");
    var old = NearbyServiceContext.context(NearbyServiceTestData.one(), false);
    Test.assertEqualMessage("[1001]",
        NearbyCoverageTestData.codes([old], [] as Array<Number>, 3),
        "expired remains legacy");
    var malformed = NearbyServiceTestData.one();
    malformed["i"] = ["0"];
    Test.assertEqualMessage("[1001]",
        NearbyCoverageTestData.codes([NearbyServiceContext.context(malformed, true)],
            [] as Array<Number>, 3), "malformed context remains legacy");
    return true;
}

(:test, :nearby)
function testCoveragePageTransitions(logger as Logger) as Boolean {
    var rows = [[1001, 0, 1, "Near"], [1002, 0, 2, "Covered"],
                [1003, 0, 3, "Needed"]];
    var context = NearbyCoverageTestData.context(rows, ["00", "00", "01"], []);
    var favourites = [2001, 2002] as Array<Number>;
    var split = NearbyCoverageSelection.select([context], 0, 0, favourites, 3);
    var ordered = NearbyPageOrder.build(favourites, split[0] as Array,
        split[1] as Array, 1, NearbyPageOrder.READY);
    Test.assertEqualMessage("[2001, 1001, 1003, 2002]",
        NearbyStopMathsTestData.codes(ordered),
        "configured favourite positions and no duplicated nearby page");
    var pages = NearbyPageOrderTestPages.fromOrder(ordered);
    Test.assertEqualMessage(-1, NearbyPageOrder.preserve(
        {"stopId" => 1002, "nearby" => true}, pages, 1),
        "viewed stop removed by coverage stays until Select");
    Test.assertEqualMessage(0, NearbyPageOrder.nextIndex(3, ordered.size()),
        "Select wraps after coverage rebuild");
    var empty = NearbyCoverageSelection.select(
        [NearbyCoverageTestData.context([] as Array, [] as Array, [] as Array)],
        0, 0, favourites, 3);
    var slot = NearbyPageOrder.build(favourites, empty[0] as Array,
        empty[1] as Array, 1, NearbyPageOrder.EMPTY);
    Test.assertMessage((slot[1] as Array)[NearbyStopMaths.PAGE_CODE] == null,
        "no selected stops retains configured status slot");
    return true;
}
