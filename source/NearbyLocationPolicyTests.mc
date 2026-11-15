import Toybox.Lang;
import Toybox.Position;
import Toybox.Test;

(:test, :nearby)
function testNearbyLocationPolicy(logger as Logger) as Boolean {
    var now = 5000;
    var missing = NearbyLocationPolicy.decide(Position.QUALITY_NOT_AVAILABLE, now, now);
    Test.assertEqualMessage(false, missing[0], "no position");
    Test.assertEqualMessage(true, missing[2], "acquire without position");
    var exact = NearbyLocationPolicy.decide(Position.QUALITY_GOOD, now - 600, now);
    Test.assertEqualMessage(true, exact[0], "position at ten minutes usable");
    Test.assertEqualMessage(false, exact[1], "exactly 600 seconds is recent");
    Test.assertEqualMessage(false, exact[2], "recent good fix needs no acquisition");
    var old = NearbyLocationPolicy.decide(Position.QUALITY_GOOD, now - 601, now);
    Test.assertEqualMessage(true, old[1], "601 seconds stale");
    Test.assertEqualMessage(true, old[2], "acquire new fix");
    var ancient = NearbyLocationPolicy.decide(Position.QUALITY_LAST_KNOWN, 1, now);
    Test.assertEqualMessage(true, ancient[0], "no hard age cap");
    Test.assertEqualMessage(true, ancient[1], "very old position marked stale");
    var unknown = NearbyLocationPolicy.decide(Position.QUALITY_USABLE, null, now);
    Test.assertEqualMessage(true, unknown[0], "missing timestamp still usable");
    Test.assertEqualMessage(true, unknown[1], "unknown age marked stale");
    Test.assertEqualMessage(true, unknown[2], "unknown age requests fix");
    var skew = NearbyLocationPolicy.decide(Position.QUALITY_GOOD, now + 1, now);
    Test.assertEqualMessage(false, skew[1], "negative age is recent");
    var lastKnown = NearbyLocationPolicy.decide(Position.QUALITY_LAST_KNOWN, now, now);
    Test.assertEqualMessage(false, lastKnown[1], "recent last known not marked stale");
    Test.assertEqualMessage(true, lastKnown[2], "last-known quality still needs fix");
    var poor = NearbyLocationPolicy.decide(Position.QUALITY_POOR, now, now);
    Test.assertEqualMessage(false, poor[2], "recent poor quality is enough");
    Test.assertEqualMessage(false, NearbyLocationPolicy.decide(Position.QUALITY_USABLE, now, now)[2],
        "recent usable quality is enough");
    return true;
}

(:test, :nearby)
function testNearbyFixIndicatorPlacement(logger as Logger) as Boolean {
    var alone = NearbyFixIndicator.rect(240, 240, false);
    var besideNetwork = NearbyFixIndicator.rect(240, 240, true);
    Test.assertEqualMessage(114, (alone as Array)[0], "centred when alone");
    Test.assertEqualMessage(91, (besideNetwork as Array)[0], "left of network icon");
    Test.assertEqualMessage(17, (besideNetwork as Array)[1], "top chord with title below");
    Test.assertMessage((besideNetwork as Array)[0] + 12 < 110,
        "does not overlap existing 20 px network icon");
    Test.assertMessage((besideNetwork as Array)[1] + 12 < 40,
        "clear of wrapped nearby title");
    Test.assertMessage(NearbyFixIndicator.rect(176, 176, true) == null,
        "skip indicator if top chord is too narrow");
    return true;
}
