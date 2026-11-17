import Toybox.Lang;
import Toybox.Test;

(:test, :nearby)
function testNearbyRefreshPolicy(logger as Logger) as Boolean {
    Test.assertMessage(NearbyRefreshPolicy.shouldRefresh(0, 0, null, null, -1, 0),
        "first tile");
    Test.assertMessage(!NearbyRefreshPolicy.shouldRefresh(89, 0, 0, 0, 0, 30),
        "less than 100 m");
    Test.assertMessage(NearbyRefreshPolicy.shouldRefresh(91, 0, 0, 0, 0, 30),
        "over 100 m");
    Test.assertMessage(!NearbyRefreshPolicy.shouldRefresh(91, 0, 0, 0, 0, 29),
        "rate limit");
    Test.assertMessage(!NearbyRefreshPolicy.shouldRefresh(91, 0, 0, 0, 31, 30),
        "clock moved backwards");
    return true;
}
