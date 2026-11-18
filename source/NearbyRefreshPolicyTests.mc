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
    var rows = [[53092, -4353000, 17263000, "Near"],
                [53093, -4352900, 17263000, "Other"]] as Array;
    Test.assertEqualMessage(NearbyStopMaths.approxMetres(-4353000, 17263000,
        -4352910, 17263000), NearbyStopMaths.metresForCode(rows, 53092,
        -4352910, 17263000), "dropped nearby stop still gets a fresh distance");
    Test.assertMessage(NearbyStopMaths.metresForCode(rows, 53094,
        -4352910, 17263000) == null, "stop absent from new tile stays stale");
    return true;
}
