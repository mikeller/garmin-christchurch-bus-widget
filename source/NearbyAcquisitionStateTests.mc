import Toybox.Lang;
import Toybox.Test;

(:test, :nearby)
function testNearbyAcquisitionLifecycle(logger as Logger) as Boolean {
    var waiting = NearbyAcquisitionState.shown();
    Test.assertMessage(NearbyAcquisitionState.registered(waiting), "shown registers");
    var late = NearbyAcquisitionState.timedOut(waiting);
    Test.assertEqualMessage(NearbyAcquisitionState.LATE, late, "60s changes label");
    Test.assertMessage(NearbyAcquisitionState.registered(late), "still listening");
    Test.assertEqualMessage(NearbyAcquisitionState.FIX,
        NearbyAcquisitionState.received(late), "late fix delivered");
    Test.assertMessage(!NearbyAcquisitionState.registered(
        NearbyAcquisitionState.received(late)), "one-shot disabled");
    var suspended = NearbyAcquisitionState.afterHide(late);
    Test.assertMessage(!NearbyAcquisitionState.registered(suspended), "hide disables");
    Test.assertMessage(NearbyAcquisitionState.registered(
        NearbyAcquisitionState.shown()), "show registers anew");
    return true;
}
