import Toybox.Lang;
import Toybox.Test;

(:test, :nearby)
function testNearbyDepartureFailureState(logger as Logger) as Boolean {
    Test.assertMessage(!NearbyDepartureState.failed(false, false, true, false),
        "stale cache pending");
    Test.assertMessage(!NearbyDepartureState.failed(false, true, false, false),
        "fresh response");
    Test.assertMessage(NearbyDepartureState.failed(false, true, true, false),
        "failed response");
    Test.assertMessage(NearbyDepartureState.failed(false, false, true, true),
        "timeout");
    Test.assertMessage(!NearbyDepartureState.failed(true, true, false, false),
        "successful retry clears failure");
    Test.assertMessage(NearbyDepartureState.failed(true, false, true, false),
        "cached result does not clear failure");
    return true;
}
