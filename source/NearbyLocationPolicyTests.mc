import Toybox.Lang;
import Toybox.Position;
import Toybox.Test;

(:test, :nearby)
function testNearbyLocationPolicy(logger as Logger) as Boolean {
    var now = 5000;
    Test.assertMessage(!NearbyLocationPolicy.accepts(Position.QUALITY_NOT_AVAILABLE, now, now),
        "not available");
    Test.assertMessage(!NearbyLocationPolicy.accepts(Position.QUALITY_LAST_KNOWN, null, now),
        "missing timestamp");
    Test.assertMessage(!NearbyLocationPolicy.accepts(Position.QUALITY_LAST_KNOWN, now + 1, now),
        "clock skew");
    Test.assertMessage(NearbyLocationPolicy.accepts(Position.QUALITY_LAST_KNOWN, now - 1800, now),
        "last known at 30 minutes");
    Test.assertMessage(!NearbyLocationPolicy.accepts(Position.QUALITY_LAST_KNOWN, now - 1801, now),
        "last known past 30 minutes");
    Test.assertMessage(NearbyLocationPolicy.accepts(Position.QUALITY_POOR, now - 300, now),
        "poor at five minutes");
    Test.assertMessage(!NearbyLocationPolicy.accepts(Position.QUALITY_POOR, now - 301, now),
        "poor past five minutes");
    Test.assertMessage(NearbyLocationPolicy.accepts(Position.QUALITY_USABLE, now, now),
        "usable");
    Test.assertMessage(NearbyLocationPolicy.accepts(Position.QUALITY_GOOD, now, now),
        "good");
    Test.assertMessage(!NearbyLocationPolicy.accepts(Position.QUALITY_GOOD, null, now),
        "good without timestamp");
    return true;
}
