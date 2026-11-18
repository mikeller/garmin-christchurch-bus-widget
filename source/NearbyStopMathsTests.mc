import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;

// Unit tests for NearbyStopMaths. Compiled only with the unit test flag
// (monkeyc -t), and only for devices that keep the nearby feature.
//
//   monkeyc -d <device> -f monkey.jungle -o out/test_<device>.prg -y <key.der> -t -w
//   monkeydo out/test_<device>.prg <device> -t
//
// The vectors for toE5, tileId and nearest mirror the shared file
// tools/stoptiles/test_vectors.json (the stop tile generator), which the
// Python generator tests also pass. Keep both in step.
//
// Each test restarts the app in the simulator, so these tests are pure and
// assert nothing about network state.

// Test fixtures. Not tests themselves (no (:test) annotation, which would make
// the runner call them), and left out of release builds by :debug.
(:debug, :nearby)
class NearbyStopMathsTestData {
    // "nearest" stops of test_vectors.json: [stopCode, latE5, lonE5, name].
    static function vectorStops() as Array {
        return [
            [3001, -4352200, 17263000, "Stop A"],
            [3002, -4353000, 17264000, "Stop B"],
            [3003, -4353100, 17263000, "Stop C"],
            [1500, -4352700, 17263000, "Stop D"],
            [2000, -4353300, 17263000, "Stop E"],
            [3004, -4353000, 17262500, "Stop F"],
            [3005, -4352000, 17264000, "Stop G"],
            [3006, -4355000, 17263000, "Stop H"],
        ];
    }

    // The stop codes of a result or page list, as a string such as
    // "[3003, 1500]" so that a failure shows both lists.
    static function codes(entries as Array) as String {
        var result = [] as Array<Number>;
        for (var i = 0; i < entries.size(); i++) {
            result.add((entries[i] as Array)[0] as Number);
        }

        return result.toString();
    }

    // Metres of the entries, as a string such as "[111, 334]".
    static function metres(entries as Array, index as Number) as String {
        var result = [] as Array;
        for (var i = 0; i < entries.size(); i++) {
            result.add((entries[i] as Array)[index]);
        }

        return result.toString();
    }

    // Great circle distance in metres (haversine, mean earth radius).
    static function haversine(latE5a as Number, lonE5a as Number, latE5b as Number, lonE5b as Number) as Double {
        var toRad = Math.PI.toDouble() / 180.0d / 100000.0d;
        var lat1 = latE5a.toDouble() * toRad;
        var lat2 = latE5b.toDouble() * toRad;
        var sinLat = Math.sin((lat2 - lat1) / 2.0d).toDouble();
        var sinLon = Math.sin((lonE5b - lonE5a).toDouble() * toRad / 2.0d).toDouble();
        var a = sinLat * sinLat + Math.cos(lat1).toDouble() * Math.cos(lat2).toDouble() * sinLon * sinLon;

        return 2.0d * 6371008.8d * Math.asin(Math.sqrt(a)).toDouble();
    }

    static function checkNearest(logger as Logger, latE5 as Number, lonE5 as Number, n as Number, expected as String) as Void {
        var found = NearbyStopMaths.nearest(vectorStops(), latE5, lonE5, n);
        Test.assertEqualMessage(expected, codes(found), "nearest " + n + " of " + latE5 + "," + lonE5);
    }
}

// ---- toE5 ----

(:test, :nearby)
function testToE5Vectors(logger as Logger) as Boolean {
    // "e5Rounding" in test_vectors.json (decimal strings there; the doubles
    // below round identically, none of them sits on an exact binary tie).
    Test.assertEqualMessage(-4353100, NearbyStopMaths.toE5(-43.531005d), "-43.531005");
    Test.assertEqualMessage(-4353101, NearbyStopMaths.toE5(-43.531006d), "-43.531006");
    Test.assertEqualMessage(-4353100, NearbyStopMaths.toE5(-43.531004d), "-43.531004");
    Test.assertEqualMessage(17263701, NearbyStopMaths.toE5(172.637005d), "172.637005");
    Test.assertEqualMessage(17263700, NearbyStopMaths.toE5(172.637004d), "172.637004");
    Test.assertEqualMessage(-4357000, NearbyStopMaths.toE5(-43.57d), "-43.57");
    Test.assertEqualMessage(1, NearbyStopMaths.toE5(0.000005d), "0.000005");
    Test.assertEqualMessage(0, NearbyStopMaths.toE5(-0.000005d), "-0.000005");
    Test.assertEqualMessage(-1, NearbyStopMaths.toE5(-0.000006d), "-0.000006");
    Test.assertEqualMessage(17210665, NearbyStopMaths.toE5(172.10665d), "172.10665");

    return true;
}

(:test, :nearby)
function testToE5Extras(logger as Logger) as Boolean {
    Test.assertEqualMessage(0, NearbyStopMaths.toE5(0.0d), "0");
    Test.assertEqualMessage(-1, NearbyStopMaths.toE5(-0.00001d), "-1e-5");
    Test.assertEqualMessage(-4353000, NearbyStopMaths.toE5(-43.53d), "-43.53");
    Test.assertEqualMessage(-4353001, NearbyStopMaths.toE5(-43.53001d), "-43.53001");
    Test.assertEqualMessage(17263700, NearbyStopMaths.toE5(172.637d), "172.637");
    // All eight digits survive (a Float cannot hold 17263701).
    Test.assertEqualMessage(17263701, NearbyStopMaths.toE5(172.63701d), "172.63701");

    return true;
}

// ---- floorDiv and tileId ----

(:test, :nearby)
function testFloorDiv(logger as Logger) as Boolean {
    Test.assertEqualMessage(0, NearbyStopMaths.floorDiv(0, 1000), "0");
    Test.assertEqualMessage(0, NearbyStopMaths.floorDiv(999, 1000), "999");
    Test.assertEqualMessage(1, NearbyStopMaths.floorDiv(1000, 1000), "1000");
    Test.assertEqualMessage(-1, NearbyStopMaths.floorDiv(-1, 1000), "-1");
    Test.assertEqualMessage(-1, NearbyStopMaths.floorDiv(-1000, 1000), "-1000");
    Test.assertEqualMessage(-2, NearbyStopMaths.floorDiv(-1001, 1000), "-1001");
    Test.assertEqualMessage(-4, NearbyStopMaths.floorDiv(-7, 2), "-7 / 2");
    Test.assertEqualMessage(3, NearbyStopMaths.floorDiv(7, 2), "7 / 2");

    return true;
}

(:test, :nearby)
function testTileIdVectors(logger as Logger) as Boolean {
    // "tileId" in test_vectors.json: [e5, tile, trap]. A trap is where
    // truncating division would be wrong.
    var vectors = [
        [-4353100, -4354],
        [-4353000, -4353],
        [-4353001, -4354],
        [-4352999, -4353],
        [-4354000, -4354],
        [-4354001, -4355],
        [-4353999, -4354],
        [-4299999, -4300],
        [-4357000, -4357], // stop code 25660, a real boundary stop
        [17263700, 17263],
        [17263999, 17263],
        [17264000, 17264],
    ];

    for (var i = 0; i < vectors.size(); i++) {
        var e5 = vectors[i][0] as Number;
        var tile = vectors[i][1] as Number;
        // The same rule applies to latitude and longitude.
        Test.assertEqualMessage(tile, NearbyStopMaths.floorDiv(e5, 1000), "floorDiv " + e5);
        Test.assertEqualMessage(tile, NearbyStopMaths.tileId(e5, 0)[0], "ty " + e5);
        Test.assertEqualMessage(tile, NearbyStopMaths.tileId(0, e5)[1], "tx " + e5);
    }

    return true;
}

(:test, :nearby)
function testTileIdFromDegrees(logger as Logger) as Boolean {
    // Round to E5 first, then floor: -43.531005 is E5 -4353100, tile -4354.
    var tile = NearbyStopMaths.tileId(NearbyStopMaths.toE5(-43.531005d), NearbyStopMaths.toE5(172.637004d));
    Test.assertEqualMessage(-4354, tile[0], "ty");
    Test.assertEqualMessage(17263, tile[1], "tx");

    // Stop 25660 sits exactly on a tile edge.
    tile = NearbyStopMaths.tileId(NearbyStopMaths.toE5(-43.57d), NearbyStopMaths.toE5(172.6d));
    Test.assertEqualMessage(-4357, tile[0], "ty 25660");
    Test.assertEqualMessage(17260, tile[1], "tx 25660");

    return true;
}

// ---- distance ----

(:test, :nearby)
function testApproxMetresAgainstHaversine(logger as Logger) as Boolean {
    // Within 5% of haversine up to 3 km at Christchurch latitude (the error
    // is below 0.1 percent at this latitude, apart from the rounding to
    // whole metres below 100 m).
    var latE5 = -4353200;
    var lonE5 = 17263620;
    var offsets = [
        [900, 0],
        [0, 1240],
        [-1800, 1500],
        [-2700, 0],
        [0, 3100],
        [2000, -2500],
        [90, 0],
        [0, 124],
    ];

    for (var i = 0; i < offsets.size(); i++) {
        var dLat = offsets[i][0] as Number;
        var dLon = offsets[i][1] as Number;
        var approx = NearbyStopMaths.approxMetres(latE5 + dLat, lonE5 + dLon, latE5, lonE5);
        var reference = NearbyStopMathsTestData.haversine(latE5 + dLat, lonE5 + dLon, latE5, lonE5);
        Test.assertMessage(reference <= 3010.0d, "reference up to 3 km");
        var error = (approx.toDouble() - reference).abs();
        Test.assertMessage(error <= reference * 0.05d, "dLat " + dLat + " dLon " + dLon + ": " + approx + " m, haversine " + reference + " m");
    }

    return true;
}

(:test, :nearby)
function testApproxMetresExact(logger as Logger) as Boolean {
    Test.assertEqualMessage(0, NearbyStopMaths.approxMetres(-4353000, 17263000, -4353000, 17263000), "same point");
    // 1000 E5 of latitude is 1.112 km.
    Test.assertEqualMessage(1112, NearbyStopMaths.approxMetres(-4352000, 17263000, -4353000, 17263000), "1000 N");
    Test.assertEqualMessage(1112, NearbyStopMaths.approxMetres(-4354000, 17263000, -4353000, 17263000), "1000 S");
    // 1000 E5 of longitude is 1.112 * 0.725 = 806.2 m.
    Test.assertEqualMessage(806, NearbyStopMaths.approxMetres(-4353000, 17264000, -4353000, 17263000), "1000 E");
    Test.assertEqualMessage(806, NearbyStopMaths.approxMetres(-4353000, 17262000, -4353000, 17263000), "1000 W");

    return true;
}

(:test, :nearby)
function testDistanceSquaredIsExact(logger as Logger) as Boolean {
    // (dLat * 1000)^2 + (dLon * 725)^2 in Long, as in test_vectors.json.
    var d2 = NearbyStopMaths.distanceSquared(-4352700, 17263000, -4353000, 17263000);
    Test.assertEqualMessage(90000000000l, d2, "300 E5 of latitude");
    d2 = NearbyStopMaths.distanceSquared(-4353000, 17264000, -4353000, 17263000);
    Test.assertEqualMessage(525625000000l, d2, "1000 E5 of longitude");
    // The result is more than 32 bits wide.
    d2 = NearbyStopMaths.distanceSquared(-4352000, 17264000, -4353000, 17263000);
    Test.assertEqualMessage(1525625000000l, d2, "1000 and 1000");

    return true;
}

(:test, :nearby)
function testDistanceDoesNotOverflow(logger as Logger) as Boolean {
    // A 32-bit Number overflows once (dLat * 1000)^2 exceeds 2^31, that is
    // from a delta of about 46 E5 units; these deltas are millions.
    var d2 = NearbyStopMaths.distanceSquared(-4353000 + 1000000, 17263000, -4353000, 17263000);
    Test.assertEqualMessage(1000000000000000000l, d2, "1e6 E5 of latitude");

    // Antipodal-scale deltas (whole earth), as from a corrupt tile or a bad
    // fix, are clamped: positive, no wrap-around, and symmetric.
    var far1 = NearbyStopMaths.distanceSquared(-9000000, -18000000, 9000000, 18000000);
    var far2 = NearbyStopMaths.distanceSquared(9000000, 18000000, -9000000, -18000000);
    Test.assertMessage(far1 > 0l, "far distance is positive");
    Test.assertEqualMessage(far1, far2, "far distance is symmetric");
    Test.assertMessage(far1 >= d2, "far distance is not smaller than a nearer one");
    Test.assertMessage(NearbyStopMaths.approxMetres(-9000000, -18000000, 9000000, 18000000) > 2000000, "far metres");

    return true;
}

// ---- movedMoreThan ----

(:test, :nearby)
function testMovedMoreThanLatitude(logger as Logger) as Boolean {
    var lat = -4353000;
    var lon = 17263000;
    // 100 m is 89.9 E5 of latitude: 89 is 99.0 m, 90 is 100.1 m.
    Test.assertMessage(!NearbyStopMaths.movedMoreThan(lat + 89, lon, lat, lon, 100), "89 N");
    Test.assertMessage(NearbyStopMaths.movedMoreThan(lat + 90, lon, lat, lon, 100), "90 N");
    Test.assertMessage(!NearbyStopMaths.movedMoreThan(lat - 89, lon, lat, lon, 100), "89 S");
    Test.assertMessage(NearbyStopMaths.movedMoreThan(lat - 90, lon, lat, lon, 100), "90 S");
    // Argument order does not matter.
    Test.assertMessage(NearbyStopMaths.movedMoreThan(lat, lon, lat + 90, lon, 100), "swapped");

    return true;
}

(:test, :nearby)
function testMovedMoreThanLongitude(logger as Logger) as Boolean {
    var lat = -4353000;
    var lon = 17263000;
    // 100 m is 124.0 E5 of longitude (scaled by 0.725): 124 is 99.97 m, 125
    // is 100.8 m.
    Test.assertMessage(!NearbyStopMaths.movedMoreThan(lat, lon + 124, lat, lon, 100), "124 E");
    Test.assertMessage(NearbyStopMaths.movedMoreThan(lat, lon + 125, lat, lon, 100), "125 E");
    Test.assertMessage(!NearbyStopMaths.movedMoreThan(lat, lon - 124, lat, lon, 100), "124 W");
    Test.assertMessage(NearbyStopMaths.movedMoreThan(lat, lon - 125, lat, lon, 100), "125 W");

    return true;
}

(:test, :nearby)
function testMovedMoreThanDiagonalAndSame(logger as Logger) as Boolean {
    var lat = -4353000;
    var lon = 17263000;
    Test.assertMessage(!NearbyStopMaths.movedMoreThan(lat, lon, lat, lon, 100), "same point");
    // sqrt(dLat^2 + (dLon * 0.725)^2) * 1.112: 70 and 70 is 96.1 m (no),
    // 75 and 75 is 103.0 m (yes), in either direction.
    Test.assertMessage(!NearbyStopMaths.movedMoreThan(lat + 70, lon + 70, lat, lon, 100), "70 and 70");
    Test.assertMessage(!NearbyStopMaths.movedMoreThan(lat - 70, lon - 70, lat, lon, 100), "-70 and -70");
    Test.assertMessage(NearbyStopMaths.movedMoreThan(lat + 75, lon + 75, lat, lon, 100), "75 and 75");
    Test.assertMessage(NearbyStopMaths.movedMoreThan(lat - 75, lon - 75, lat, lon, 100), "-75 and -75");
    // Far moves and a corrupt jump do not overflow.
    Test.assertMessage(NearbyStopMaths.movedMoreThan(lat + 20000000, lon + 30000000, lat, lon, 100), "huge");

    return true;
}

// ---- nearest ----

(:test, :nearby)
function testNearestVectors(logger as Logger) as Boolean {
    // "nearest" queries of test_vectors.json. D (1500) and E (2000) tie, the
    // lower code is first; B (dLon 1000) is nearer than A (dLat 800) because
    // dLon is scaled by 0.725.
    NearbyStopMathsTestData.checkNearest(logger, -4353000, 17263000, 5, "[3003, 1500, 2000, 3004, 3002]");
    NearbyStopMathsTestData.checkNearest(logger, -4352200, 17263000, 5, "[3001, 1500, 3005, 3004, 3003]");
    NearbyStopMathsTestData.checkNearest(logger, -4352200, 17263000, 3, "[3001, 1500, 3005]");
    // count larger than the stop count returns all stops.
    NearbyStopMathsTestData.checkNearest(logger, -4353000, 17263000, 20, "[3003, 1500, 2000, 3004, 3002, 3001, 3005, 3006]");

    return true;
}

(:test, :nearby)
function testNearestMetresAndNames(logger as Logger) as Boolean {
    var found = NearbyStopMaths.nearest(NearbyStopMathsTestData.vectorStops(), -4353000, 17263000, 5);
    Test.assertEqualMessage(5, found.size(), "size");
    Test.assertEqualMessage("[111, 334, 334, 403, 806]", NearbyStopMathsTestData.metres(found, NearbyStopMaths.ENTRY_METRES), "metres");
    // The raw tile name is passed through.
    Test.assertEqualMessage("Stop C", (found[0] as Array)[NearbyStopMaths.ENTRY_NAME] as Object?, "name of first");
    Test.assertEqualMessage("Stop E", (found[2] as Array)[NearbyStopMaths.ENTRY_NAME] as Object?, "name of third");

    return true;
}

(:test, :nearby)
function testNearestEmptyAndZero(logger as Logger) as Boolean {
    Test.assertEqualMessage(0, NearbyStopMaths.nearest([] as Array, -4353000, 17263000, 5).size(), "empty tile");
    Test.assertEqualMessage(0, NearbyStopMaths.nearest(NearbyStopMathsTestData.vectorStops(), -4353000, 17263000, 0).size(), "n = 0");
    Test.assertEqualMessage(0, NearbyStopMaths.nearest(NearbyStopMathsTestData.vectorStops(), -4353000, 17263000, -1).size(), "n < 0");
    NearbyStopMathsTestData.checkNearest(logger, -4353000, 17263000, 1, "[3003]");

    return true;
}

(:test, :nearby)
function testNearestTiesAndOrder(logger as Logger) as Boolean {
    // Equal distances, listed with descending codes: the lower code wins even
    // when it arrives last, and also when it falls outside n.
    var stops = [
        [40, -4353100, 17263000, "N-S"],
        [30, -4352900, 17263000, "N-N"],
        [20, -4353000, 17263138, "E"],
        [10, -4353000, 17262862, "W"],
        [5, -4353000, 17263000, "Here"],
    ];
    var codes = NearbyStopMathsTestData.codes(NearbyStopMaths.nearest(stops, -4353000, 17263000, 5));
    // N-S and N-N are 100 E5 of latitude away; E and W are 138 * 0.725 = 100.05.
    Test.assertEqualMessage("[5, 30, 40, 10, 20]", codes, "ties by code");

    codes = NearbyStopMathsTestData.codes(NearbyStopMaths.nearest(stops, -4353000, 17263000, 2));
    Test.assertEqualMessage("[5, 30]", codes, "ties cut by n");

    // A single stop, any n.
    codes = NearbyStopMathsTestData.codes(NearbyStopMaths.nearest([[7, -4353000, 17263000, "X"]], -4353000, 17263000, 5));
    Test.assertEqualMessage("[7]", codes, "single stop");

    return true;
}

(:test, :nearby)
function testNearestOverflowDeltas(logger as Logger) as Boolean {
    var q = -4353000;
    var p = 17263000;
    // Deltas of hundreds of thousands to millions of E5 units: unguarded 32
    // bit maths overflows. The ordering must still be by distance.
    var stops = [
        [1, q, p + 1500000, "F"],
        [2, q + 1000000, p, "D"],
        [3, q, p + 20, "A"],
        [4, q - 600000, p + 600000, "E"],
        [5, q + 50000, p, "B"],
        [6, q, p - 300000, "C"],
    ];
    var codes = NearbyStopMathsTestData.codes(NearbyStopMaths.nearest(stops, q, p, 6));
    // Distances (E5, lon * 0.725): A 14.5, B 50000, C 217500, E 600000 and
    // 435000 = 741000, D 1000000, F 1087500.
    Test.assertEqualMessage("[3, 5, 6, 4, 2, 1]", codes, "ordering with huge deltas");

    // Whole-earth deltas are clamped, never negative or wrapped, and a near
    // stop still wins.
    stops = [
        [9, 9000000, -18000000, "far"],
        [8, -9000000, 18000000, "far"],
        [7, q, p + 100, "near"],
    ];
    codes = NearbyStopMathsTestData.codes(NearbyStopMaths.nearest(stops, q, p, 3));
    Test.assertEqualMessage("[7, 8, 9]", codes, "clamped far stops after the near one");

    return true;
}

(:test, :nearby)
function testNearestLargeTileKeepsFive(logger as Logger) as Boolean {
    // 60 stops on a line going away from the query, listed in a scrambled
    // order, to exercise the bounded insertion past the fifth entry.
    var stops = [] as Array;
    for (var i = 0; i < 60; i++) {
        var k = (i * 37) % 60; // 37 is coprime to 60: a permutation of 0..59
        stops.add([1000 + k, -4353000 + k * 10, 17263000, "S" + k]);
    }

    var found = NearbyStopMaths.nearest(stops, -4353000, 17263000, 5);
    Test.assertEqualMessage("[1000, 1001, 1002, 1003, 1004]", NearbyStopMathsTestData.codes(found), "five nearest");
    Test.assertEqualMessage("[0, 11, 22, 33, 44]", NearbyStopMathsTestData.metres(found, NearbyStopMaths.ENTRY_METRES), "metres");

    return true;
}

// ---- nearestSplit ----

(:test, :nearby)
function testSplitFavouriteAlsoNearby(logger as Logger) as Boolean {
    // Favourite C (3003) is the nearest stop: it is not repeated in the
    // non-favourite list, and carries its distance.
    var split = NearbyStopMaths.nearestSplit(NearbyStopMathsTestData.vectorStops(), -4353000, 17263000, [3003], 5);
    var nonFavourites = split[0] as Array;
    var favouriteNearby = split[1] as Array;
    Test.assertEqualMessage("[1500, 2000, 3004, 3002, 3001]", NearbyStopMathsTestData.codes(nonFavourites), "non-favourites");
    Test.assertEqualMessage("[3003]", NearbyStopMathsTestData.codes(favouriteNearby), "favourite nearby");
    Test.assertEqualMessage("[111]", NearbyStopMathsTestData.metres(favouriteNearby, NearbyStopMaths.ENTRY_METRES), "favourite metres");

    // Page order: no second page for the favourite, distance on it.
    var pages = NearbyStopMaths.buildPageOrder([3003], nonFavourites, favouriteNearby, 1);
    Test.assertEqualMessage("[3003, 1500, 2000, 3004, 3002, 3001]", NearbyStopMathsTestData.codes(pages), "pages");
    Test.assertEqualMessage(111, (pages[0] as Array)[NearbyStopMaths.PAGE_METRES] as Object?, "distance on the favourite");
    Test.assertEqualMessage(true, (pages[0] as Array)[NearbyStopMaths.PAGE_IS_FAVOURITE] as Object?, "is favourite");
    Test.assertEqualMessage(false, (pages[1] as Array)[NearbyStopMaths.PAGE_IS_FAVOURITE] as Object?, "nearby is not favourite");
    Test.assertEqualMessage("Stop D", (pages[1] as Array)[NearbyStopMaths.PAGE_NAME] as Object?, "nearby name");

    return true;
}

(:test, :nearby)
function testSplitFavouriteInTileButNotNearest(logger as Logger) as Boolean {
    // H (3006) is the eighth nearest and G (3005) the seventh: no distance.
    var split = NearbyStopMaths.nearestSplit(NearbyStopMathsTestData.vectorStops(), -4353000, 17263000, [3006, 3005], 5);
    var nonFavourites = split[0] as Array;
    var favouriteNearby = split[1] as Array;
    Test.assertEqualMessage("[3003, 1500, 2000, 3004, 3002]", NearbyStopMathsTestData.codes(nonFavourites), "non-favourites");
    Test.assertEqualMessage("[]", NearbyStopMathsTestData.codes(favouriteNearby), "no favourite nearby");

    var pages = NearbyStopMaths.buildPageOrder([3006, 3005], nonFavourites, favouriteNearby, 2);
    Test.assertEqualMessage("[3006, 3005, 3003, 1500, 2000, 3004, 3002]", NearbyStopMathsTestData.codes(pages), "pages");
    Test.assertMessage(((pages[0] as Array)[NearbyStopMaths.PAGE_METRES] as Object?) == null, "no distance 3006");
    Test.assertMessage(((pages[1] as Array)[NearbyStopMaths.PAGE_METRES] as Object?) == null, "no distance 3005");
    Test.assertEqualMessage(334, (pages[3] as Array)[NearbyStopMaths.PAGE_METRES] as Object?, "nearby has distance");

    return true;
}

(:test, :nearby)
function testSplitFavouriteNotInTile(logger as Logger) as Boolean {
    var split = NearbyStopMaths.nearestSplit(NearbyStopMathsTestData.vectorStops(), -4353000, 17263000, [99999], 5);
    var nonFavourites = split[0] as Array;
    var favouriteNearby = split[1] as Array;
    Test.assertEqualMessage("[3003, 1500, 2000, 3004, 3002]", NearbyStopMathsTestData.codes(nonFavourites), "non-favourites");
    Test.assertEqualMessage("[]", NearbyStopMathsTestData.codes(favouriteNearby), "no favourite nearby");

    var pages = NearbyStopMaths.buildPageOrder([99999], nonFavourites, favouriteNearby, 5);
    Test.assertEqualMessage("[99999, 3003, 1500, 2000, 3004, 3002]", NearbyStopMathsTestData.codes(pages), "pages");
    Test.assertMessage(((pages[0] as Array)[NearbyStopMaths.PAGE_METRES] as Object?) == null, "no distance");

    return true;
}

(:test, :nearby)
function testSplitNoFavourites(logger as Logger) as Boolean {
    var split = NearbyStopMaths.nearestSplit(NearbyStopMathsTestData.vectorStops(), -4353000, 17263000, [] as Array<Number>, 5);
    var nonFavourites = split[0] as Array;
    var favouriteNearby = split[1] as Array;
    Test.assertEqualMessage("[3003, 1500, 2000, 3004, 3002]", NearbyStopMathsTestData.codes(nonFavourites), "non-favourites");
    Test.assertEqualMessage("[]", NearbyStopMathsTestData.codes(favouriteNearby), "no favourite nearby");

    var pages = NearbyStopMaths.buildPageOrder([] as Array<Number>, nonFavourites, favouriteNearby, 5);
    Test.assertEqualMessage("[3003, 1500, 2000, 3004, 3002]", NearbyStopMathsTestData.codes(pages), "pages");

    return true;
}

(:test, :nearby)
function testSplitAllNearestAreFavourites(logger as Logger) as Boolean {
    var favourites = [3002, 3003, 1500, 2000, 3004]; // the five nearest
    var split = NearbyStopMaths.nearestSplit(NearbyStopMathsTestData.vectorStops(), -4353000, 17263000, favourites, 5);
    var nonFavourites = split[0] as Array;
    var favouriteNearby = split[1] as Array;
    // The nearby section is filled from the next nearest non-favourites.
    Test.assertEqualMessage("[3001, 3005, 3006]", NearbyStopMathsTestData.codes(nonFavourites), "next nearest non-favourites");
    Test.assertEqualMessage("[3003, 1500, 2000, 3004, 3002]", NearbyStopMathsTestData.codes(favouriteNearby), "all five nearest");
    Test.assertEqualMessage("[111, 334, 334, 403, 806]", NearbyStopMathsTestData.metres(favouriteNearby, NearbyStopMaths.ENTRY_METRES), "favourite metres");

    var pages = NearbyStopMaths.buildPageOrder(favourites, nonFavourites, favouriteNearby, 2);
    Test.assertEqualMessage("[3002, 3003, 3001, 3005, 3006, 1500, 2000, 3004]", NearbyStopMathsTestData.codes(pages), "pages");
    Test.assertEqualMessage("[806, 111, 890, 1374, 2224, 334, 334, 403]", NearbyStopMathsTestData.metres(pages, NearbyStopMaths.PAGE_METRES), "page metres");

    // A tile with only favourites: the nearby section is empty.
    var onlyFavourites = [3001, 3002, 3003, 1500, 2000, 3004, 3005, 3006];
    split = NearbyStopMaths.nearestSplit(NearbyStopMathsTestData.vectorStops(), -4353000, 17263000, onlyFavourites, 5);
    Test.assertEqualMessage("[]", NearbyStopMathsTestData.codes(split[0] as Array), "no non-favourites in the tile");
    Test.assertEqualMessage("[3003, 1500, 2000, 3004, 3002]", NearbyStopMathsTestData.codes(split[1] as Array), "five nearest favourites");

    pages = NearbyStopMaths.buildPageOrder(onlyFavourites, split[0] as Array, split[1] as Array, 0);
    Test.assertEqualMessage("[3001, 3002, 3003, 1500, 2000, 3004, 3005, 3006]", NearbyStopMathsTestData.codes(pages), "pages with favourites only");

    return true;
}

(:test, :nearby)
function testSplitFewerThanFiveNonFavourites(logger as Logger) as Boolean {
    // Four of the eight stops are favourites: only four non-favourites.
    var split = NearbyStopMaths.nearestSplit(NearbyStopMathsTestData.vectorStops(), -4353000, 17263000, [3003, 1500, 3001, 3006], 5);
    Test.assertEqualMessage("[2000, 3004, 3002, 3005]", NearbyStopMathsTestData.codes(split[0] as Array), "four non-favourites");
    Test.assertEqualMessage("[3003, 1500]", NearbyStopMathsTestData.codes(split[1] as Array), "favourites among the five nearest");

    // An empty tile.
    split = NearbyStopMaths.nearestSplit([] as Array, -4353000, 17263000, [3003], 5);
    Test.assertEqualMessage("[]", NearbyStopMathsTestData.codes(split[0] as Array), "empty tile");
    Test.assertEqualMessage("[]", NearbyStopMathsTestData.codes(split[1] as Array), "empty tile favourites");
    var pages = NearbyStopMaths.buildPageOrder([3003], split[0] as Array, split[1] as Array, 5);
    Test.assertEqualMessage("[3003]", NearbyStopMathsTestData.codes(pages), "only the favourite");

    return true;
}

// ---- buildPageOrder ----

(:test, :nearby)
function testPageOrderLeadingFavourites(logger as Logger) as Boolean {
    // Favourites in configured order: 3006 (not nearby), 3003 (nearest),
    // 99999 (not in the tile).
    var favourites = [3006, 3003, 99999];
    var split = NearbyStopMaths.nearestSplit(NearbyStopMathsTestData.vectorStops(), -4353000, 17263000, favourites, 5);
    var nonFavourites = split[0] as Array;
    var favouriteNearby = split[1] as Array;
    Test.assertEqualMessage("[1500, 2000, 3004, 3002, 3001]", NearbyStopMathsTestData.codes(nonFavourites), "non-favourites");
    Test.assertEqualMessage("[3003]", NearbyStopMathsTestData.codes(favouriteNearby), "favourite nearby");

    // N = 0: nearby first, then every favourite.
    var pages = NearbyStopMaths.buildPageOrder(favourites, nonFavourites, favouriteNearby, 0);
    Test.assertEqualMessage("[1500, 2000, 3004, 3002, 3001, 3006, 3003, 99999]", NearbyStopMathsTestData.codes(pages), "N = 0");
    Test.assertEqualMessage("[334, 334, 403, 806, 890, null, 111, null]", NearbyStopMathsTestData.metres(pages, NearbyStopMaths.PAGE_METRES), "N = 0 metres");

    // N = 2: two favourites, then nearby, then the remaining favourite.
    pages = NearbyStopMaths.buildPageOrder(favourites, nonFavourites, favouriteNearby, 2);
    Test.assertEqualMessage("[3006, 3003, 1500, 2000, 3004, 3002, 3001, 99999]", NearbyStopMathsTestData.codes(pages), "N = 2");
    Test.assertEqualMessage("[null, 111, 334, 334, 403, 806, 890, null]", NearbyStopMathsTestData.metres(pages, NearbyStopMaths.PAGE_METRES), "N = 2 metres");

    // N = F: every favourite first.
    pages = NearbyStopMaths.buildPageOrder(favourites, nonFavourites, favouriteNearby, 3);
    Test.assertEqualMessage("[3006, 3003, 99999, 1500, 2000, 3004, 3002, 3001]", NearbyStopMathsTestData.codes(pages), "N = F");

    // N = 16 and N greater than F: the same as N = F, no repeats.
    pages = NearbyStopMaths.buildPageOrder(favourites, nonFavourites, favouriteNearby, 16);
    Test.assertEqualMessage("[3006, 3003, 99999, 1500, 2000, 3004, 3002, 3001]", NearbyStopMathsTestData.codes(pages), "N = 16");

    return true;
}

(:test, :nearby)
function testPageOrderSixteenFavourites(logger as Logger) as Boolean {
    // The configured maximum of 16 favourites, none of them in the tile.
    var favourites = [] as Array<Number>;
    for (var i = 0; i < 16; i++) {
        favourites.add(50000 + i);
    }

    var split = NearbyStopMaths.nearestSplit(NearbyStopMathsTestData.vectorStops(), -4353000, 17263000, favourites, 5);
    var pages = NearbyStopMaths.buildPageOrder(favourites, split[0] as Array, split[1] as Array, 16);
    Test.assertEqualMessage(21, pages.size(), "16 favourites and 5 nearby");
    Test.assertEqualMessage(50000, (pages[0] as Array)[NearbyStopMaths.PAGE_CODE] as Object?, "first favourite");
    Test.assertEqualMessage(50015, (pages[15] as Array)[NearbyStopMaths.PAGE_CODE] as Object?, "last favourite");
    Test.assertEqualMessage(3003, (pages[16] as Array)[NearbyStopMaths.PAGE_CODE] as Object?, "first nearby");

    pages = NearbyStopMaths.buildPageOrder(favourites, split[0] as Array, split[1] as Array, 2);
    Test.assertEqualMessage(21, pages.size(), "N = 2 size");
    Test.assertEqualMessage(50001, (pages[1] as Array)[NearbyStopMaths.PAGE_CODE] as Object?, "second favourite");
    Test.assertEqualMessage(3003, (pages[2] as Array)[NearbyStopMaths.PAGE_CODE] as Object?, "first nearby after two favourites");
    Test.assertEqualMessage(50002, (pages[7] as Array)[NearbyStopMaths.PAGE_CODE] as Object?, "third favourite after nearby");

    return true;
}

(:test, :nearby)
function testPageOrderNoFavouritesNoNearby(logger as Logger) as Boolean {
    var pages = NearbyStopMaths.buildPageOrder([] as Array<Number>, [] as Array, [] as Array, 5);
    Test.assertEqualMessage(0, pages.size(), "nothing");
    Test.assertEqualMessage(NearbyStopMaths.NEARBY_COUNT, 5, "nearby count");

    return true;
}

(:test, :nearby)
function testNearbyOnlyOrdering(logger as Logger) as Boolean {
    var split = NearbyStopMaths.nearestSplit(NearbyStopMathsTestData.vectorStops(),
        -4353000, 17263000, [] as Array<Number>, 5);
    for (var n = 0; n <= 16; n += (n == 0 ? 2 : 14)) {
        var pages = NearbyStopMaths.buildPageOrder([] as Array<Number>,
            split[0] as Array, split[1] as Array, n);
        Test.assertEqualMessage("[3003, 1500, 2000, 3004, 3002]",
            NearbyStopMathsTestData.codes(pages), "nearby-only N=" + n);
        Test.assertEqualMessage("[]", NearbyStopMathsTestData.codes(split[1] as Array),
            "no favourite distance");
    }
    var empty = NearbyStopMaths.nearestSplit([] as Array, -4353000, 17263000,
        [] as Array<Number>, 5);
    Test.assertEqualMessage(0, NearbyStopMaths.buildPageOrder([] as Array<Number>,
        empty[0] as Array, empty[1] as Array, 0).size(), "empty tile");
    return true;
}

(:test, :nearby)
function testConfiguredNearbyCounts(logger as Logger) as Boolean {
    Test.assertEqualMessage(5, NearbyStopMaths.NEARBY_COUNT,
        "tile contract maximum: revisit the 15-stop tile minimum before increasing");
    var values = [1, 3, 5] as Array<Number>;
    var expected = ["[3003]", "[3003, 1500, 2000]",
                    "[3003, 1500, 2000, 3004, 3002]"];
    var nonFavourite = ["[1500]", "[1500, 2000, 3004]",
                        "[1500, 2000, 3004, 3002, 3001]"];
    for (var i = 0; i < values.size(); i++) {
        var n = values[i];
        var stops = NearbyStopMathsTestData.vectorStops();
        Test.assertEqualMessage(expected[i], NearbyStopMathsTestData.codes(
            NearbyStopMaths.nearest(stops, -4353000, 17263000, n)), "nearest count");
        var split = NearbyStopMaths.nearestSplit(stops, -4353000, 17263000,
            [3003] as Array<Number>, n);
        Test.assertEqualMessage(nonFavourite[i],
            NearbyStopMathsTestData.codes(split[0] as Array), "non-favourite count");
        Test.assertEqualMessage("[3003]",
            NearbyStopMathsTestData.codes(split[1] as Array), "favourite among overall n");
        var order = NearbyPageOrder.build([3003] as Array<Number>, split[0] as Array,
            split[1] as Array, 0, NearbyPageOrder.READY);
        Test.assertEqualMessage(n + 1, order.size(), "configured count plus favourite");
    }
    return true;
}

(:test, :nearby)
function testNearbyStopsToShowSetting(logger as Logger) as Boolean {
    Test.assertEqualMessage(3, NearbyAvailability.normaliseStopsToShow(null), "missing");
    Test.assertEqualMessage(3, NearbyAvailability.normaliseStopsToShow(""), "blank");
    Test.assertEqualMessage(3, NearbyAvailability.normaliseStopsToShow("4"), "string");
    Test.assertEqualMessage(3, NearbyAvailability.normaliseStopsToShow(0), "zero");
    Test.assertEqualMessage(3, NearbyAvailability.normaliseStopsToShow(-1), "negative");
    Test.assertEqualMessage(3, NearbyAvailability.normaliseStopsToShow(6), "above maximum");
    for (var n = 1; n <= 5; n++) {
        Test.assertEqualMessage(n, NearbyAvailability.normaliseStopsToShow(n), "valid setting");
    }
    return true;
}

(:test, :nearby)
function testFavouritesBeforeNearbySettingFallback(logger as Logger) as Boolean {
    Test.assertEqualMessage(0, NearbyAvailability.normaliseFavouritesBeforeNearby(null), "blank");
    Test.assertEqualMessage(0, NearbyAvailability.normaliseFavouritesBeforeNearby(""), "empty string");
    Test.assertEqualMessage(0, NearbyAvailability.normaliseFavouritesBeforeNearby("1"), "string is not numeric");
    Test.assertEqualMessage(0, NearbyAvailability.normaliseFavouritesBeforeNearby(true), "boolean is not numeric");
    Test.assertEqualMessage(0, NearbyAvailability.normaliseFavouritesBeforeNearby(-1), "below range");
    Test.assertEqualMessage(0, NearbyAvailability.normaliseFavouritesBeforeNearby(17), "above range");
    Test.assertEqualMessage(0, NearbyAvailability.normaliseFavouritesBeforeNearby(0), "nearby first");
    Test.assertEqualMessage(1, NearbyAvailability.normaliseFavouritesBeforeNearby(1), "one favourite first");
    Test.assertEqualMessage(16, NearbyAvailability.normaliseFavouritesBeforeNearby(16), "maximum");
    return true;
}
