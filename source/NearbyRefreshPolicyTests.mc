import Toybox.Lang;
import Toybox.Test;

(:test, :nearby)
function testNearbyRefreshPolicy(logger as Logger) as Boolean {
    Test.assertMessage(NearbyRefreshPolicy.shouldRefresh(0, 0, null, null, -1, 0),
        "first tile");
    Test.assertMessage(!NearbyRefreshPolicy.shouldRefresh(35, 0, 0, 0, 0, 30),
        "small movement under 50 m and 60 seconds");
    Test.assertMessage(NearbyRefreshPolicy.shouldRefresh(46, 0, 0, 0, 0, 30),
        "over 50 m after 30 seconds");
    Test.assertMessage(!NearbyRefreshPolicy.shouldRefresh(46, 0, 0, 0, 0, 29),
        "rate limit");
    Test.assertMessage(NearbyRefreshPolicy.shouldRefresh(10, 0, 0, 0, 0, 60),
        "walking ten metres for a minute reselects");
    Test.assertMessage(!NearbyRefreshPolicy.shouldRefresh(3, 0, 0, 0, 0, 60),
        "stationary jitter does not reselect");
    Test.assertMessage(!NearbyRefreshPolicy.shouldRefresh(46, 0, 0, 0, 31, 30),
        "clock moved backwards");
    Test.assertMessage(NearbyRefreshPolicy.shouldUpdateDistances(0, 0, 31, 0, 0, 30, false),
        "newer fix refreshes even without movement");
    Test.assertMessage(NearbyRefreshPolicy.shouldUpdateDistances(1, 0, 30, 0, 0, 30, false),
        "small movement refreshes distances, not nearest set");
    Test.assertMessage(NearbyRefreshPolicy.shouldUpdateDistances(0, 0, 30, 0, 0, 30, true),
        "pending data must be checked before clearing symbol");
    Test.assertMessage(!NearbyRefreshPolicy.shouldUpdateDistances(0, 0, 30, 0, 0, 30, false),
        "unchanged fix does not allocate new distance rows");
    // A full rebuild within one tile must reset coverage on movement even
    // when a forced refresh bypasses the normal 30-second rate limit.
    var lat = -4353100;
    var lon = 17263700;
    var movedLat = lat + 10;
    var tile = NearbyStopMaths.tileId(lat, lon);
    var movedTile = NearbyStopMaths.tileId(movedLat, lon);
    Test.assertEqualMessage(tile[0], movedTile[0], "movement remains in same tile");
    Test.assertEqualMessage(tile[1], movedTile[1], "longitude tile unchanged");
    Test.assertMessage(!NearbyRefreshPolicy.shouldRefresh(movedLat, lon,
        lat, lon, 100, 101), "rate limit suppresses automatic rebuild");
    Test.assertMessage(!NearbyRefreshPolicy.keepDepartureHistory(true, movedLat, lon,
        lat, lon), "forced movement rebuild resets the key union");
    Test.assertMessage(NearbyRefreshPolicy.keepDepartureHistory(true, lat, lon,
        lat, lon), "stationary forced rebuild retains the key union");
    Test.assertMessage(NearbyRefreshPolicy.keepDepartureHistory(true, lat + 3, lon,
        lat, lon), "distance-only jitter retains the key union");
    Test.assertMessage(!NearbyRefreshPolicy.keepDepartureHistory(false, lat, lon,
        lat, lon), "tile change starts a new session");
    Test.assertMessage(!NearbyRefreshPolicy.keepDepartureHistory(true, lat, lon,
        null, null), "first selection has no previous session");
    var rows = [[53092, -4353000, 17263000, "Near"],
                [53093, -4352900, 17263000, "Other"]] as Array;
    Test.assertEqualMessage(NearbyStopMaths.approxMetres(-4353000, 17263000,
        -4352910, 17263000), NearbyStopMaths.metresForCode(rows, 53092,
        -4352910, 17263000), "dropped nearby stop still gets a fresh distance");
    Test.assertMessage(NearbyStopMaths.metresForCode(rows, 53094,
        -4352910, 17263000) == null, "stop absent from new tile stays stale");
    return true;
}
