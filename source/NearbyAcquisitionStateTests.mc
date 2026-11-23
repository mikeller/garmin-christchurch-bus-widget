import Toybox.Lang;
import Toybox.Test;

(:test, :nearby)
function testNearbyAcquisitionLifecycle(logger as Logger) as Boolean {
    var waiting = NearbyAcquisitionState.shown();
    Test.assertMessage(NearbyAcquisitionState.registered(waiting), "shown registers");
    var late = NearbyAcquisitionState.timedOut(waiting);
    Test.assertEqualMessage(NearbyAcquisitionState.IDLE, late, "60s ends acquisition");
    Test.assertMessage(!NearbyAcquisitionState.registered(late), "timeout disables listener");
    var suspended = NearbyAcquisitionState.afterHide(late);
    Test.assertMessage(!NearbyAcquisitionState.registered(suspended), "hide disables");
    Test.assertMessage(NearbyAcquisitionState.registered(
        NearbyAcquisitionState.shown()), "show registers anew");
    return true;
}
