import Toybox.Lang;
import Toybox.Test;

(:test, :nearby)
function testNearbyRecheckPolicy(logger as Logger) as Boolean {
    Test.assertMessage(NearbyRecheckPolicy.eligible(true, true, false, 7,
        false, false, 10, 131), "stale dropped stop on nearby Select");
    Test.assertMessage(!NearbyRecheckPolicy.eligible(true, true, false, 7,
        false, false, 10, 130), "120 seconds is still fresh");
    Test.assertMessage(!NearbyRecheckPolicy.eligible(false, true, false, 7,
        false, false, null, 131), "no timer or position recheck");
    Test.assertMessage(!NearbyRecheckPolicy.eligible(true, false, false, 7,
        false, false, null, 131), "feature toggle");
    Test.assertMessage(!NearbyRecheckPolicy.eligible(true, true, true, 7,
        false, false, null, 131), "one concurrent recheck");
    Test.assertMessage(!NearbyRecheckPolicy.eligible(true, true, false, 8,
        false, false, null, 131), "cycle cap");
    Test.assertMessage(!NearbyRecheckPolicy.eligible(true, true, false, 7,
        true, false, null, 131), "visible page");
    Test.assertMessage(!NearbyRecheckPolicy.eligible(true, true, false, 7,
        false, true, null, 131), "request already running");
    return true;
}
