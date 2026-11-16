import Toybox.Lang;
import Toybox.Test;

(:test, :nearby)
function testNearbyGlanceStopRecord(logger as Logger) as Boolean {
    var now = 10000;
    var first = {"stopId" => 53090} as Dictionary;
    var second = {"stopId" => 53091} as Dictionary;
    var saved = {"stopId" => 53090, "at" => now - 30} as Dictionary;
    Test.assertMessage(NearbyGlanceStop.valid(saved, now), "valid stop and time");
    Test.assertMessage(NearbyGlanceStop.shouldWrite(first, null, now), "new page");
    Test.assertMessage(NearbyGlanceStop.shouldWrite(second, saved, now), "different stop");
    Test.assertMessage(!NearbyGlanceStop.shouldWrite(first, saved, now), "same id within minute");
    saved["at"] = now - 60;
    Test.assertMessage(NearbyGlanceStop.shouldWrite(first, saved, now), "same id after minute");
    Test.assertMessage(!NearbyGlanceStop.shouldWrite({"nearbySlot" => true}, saved, now),
        "status slot does not replace stop");
    Test.assertMessage(!NearbyGlanceStop.shouldWrite({"stopId" => "53090"}, saved, now),
        "malformed page cannot be stored");
    Test.assertMessage(!NearbyGlanceStop.valid(null, now), "missing record");
    Test.assertMessage(!NearbyGlanceStop.valid([53090, now] as Array, now), "wrong shape");
    Test.assertMessage(!NearbyGlanceStop.valid({"stopId" => "53090", "at" => now}, now),
        "string id");
    Test.assertMessage(!NearbyGlanceStop.valid({"stopId" => 999, "at" => now}, now),
        "out of range id");
    Test.assertMessage(!NearbyGlanceStop.valid({"stopId" => 53090, "at" => "now"}, now),
        "string timestamp");
    Test.assertMessage(!NearbyGlanceStop.valid({"stopId" => 53090, "at" => -1}, now),
        "negative timestamp");
    Test.assertMessage(!NearbyGlanceStop.valid({"stopId" => 53090, "at" => now + 86401}, now),
        "far future timestamp");
    Test.assertMessage(NearbyGlanceStop.shouldWrite(first, {"at" => "bad"}, now),
        "replace corrupt previous record");
    return true;
}
