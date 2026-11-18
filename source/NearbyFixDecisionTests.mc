import Toybox.Lang;
import Toybox.Test;

(:test, :nearby)
function testFavouriteFixIndicatorDecision(logger as Logger) as Boolean {
    Test.assertMessage(NearbyFixDecision.show(true, true, true),
        "stale favourite distance shows GPS symbol");
    Test.assertMessage(!NearbyFixDecision.show(true, true, false),
        "fresh favourite distance hides symbol");
    Test.assertMessage(!NearbyFixDecision.show(true, false, true),
        "favourite without distance never shows GPS symbol");
    Test.assertMessage(NearbyFixDecision.show(false, true, true),
        "nearby distance keeps existing symbol");
    Test.assertMessage(NearbyFixDecision.show(false, false, true),
        "status slot keeps existing GPS symbol");
    Test.assertMessage(NearbyFixDecision.staleForData(500, false, true, 501),
        "new fix cannot clear symbol while tile is pending");
    Test.assertMessage(NearbyFixDecision.staleForData(500, true, false, 502),
        "new fix cannot clear old stale selection");
    Test.assertMessage(!NearbyFixDecision.staleForData(501, false, false, 502),
        "symbol clears after distance refresh");
    Test.assertMessage(!NearbyFixDecision.staleForData(500, false, false, 800),
        "exactly 300 seconds still recent");
    Test.assertMessage(NearbyFixDecision.staleForData(500, false, false, 801),
        "301 seconds is stale");
    return true;
}
