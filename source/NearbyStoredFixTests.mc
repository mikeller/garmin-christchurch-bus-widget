import Toybox.Lang;
import Toybox.Test;

(:test, :nearby)
function testNearbyStoredFixPolicy(logger as Logger) as Boolean {
    var now = 10000;
    var old = {"v" => 1, "lat" => -4353100, "lon" => 17263700,
               "at" => 9300, "savedAt" => 9400};
    var latest = {"v" => 1, "lat" => -4353100, "lon" => 17263700, "at" => 9900};
    Test.assertMessage(NearbyStoredFix.valid(old, now), "valid E5");
    Test.assertMessage(!NearbyStoredFix.valid(null, now), "missing");
    Test.assertMessage(!NearbyStoredFix.valid({"v" => 1, "lat" => "bad",
        "lon" => 17263700, "at" => now}, now), "garbage latitude");
    Test.assertMessage(!NearbyStoredFix.valid({"v" => 1, "lat" => -9100000,
        "lon" => 17263700, "at" => now}, now), "latitude range");
    Test.assertMessage(!NearbyStoredFix.valid({"v" => 1, "lat" => -4353100,
        "lon" => 18100000, "at" => now}, now), "longitude range");
    Test.assertMessage(!NearbyStoredFix.valid({"v" => 2, "lat" => -4353100,
        "lon" => 17263700, "at" => now}, now), "version");
    Test.assertMessage(!NearbyStoredFix.valid({"v" => 1, "lat" => -4353100,
        "lon" => 17263700, "at" => -1}, now), "negative time");
    Test.assertMessage(!NearbyStoredFix.valid({"v" => 1, "lat" => -4353100,
        "lon" => 17263700, "at" => now + 86401}, now), "future time");
    Test.assertMessage(NearbyStoredFix.choose(old, latest, now) == latest, "new device fix");
    Test.assertMessage(NearbyStoredFix.choose(latest, old, now) == latest, "new stored fix");
    Test.assertMessage(NearbyStoredFix.choose(null, old, now) == old, "only stored");
    Test.assertMessage(NearbyStoredFix.choose(latest, null, now) == latest, "only device");
    Test.assertMessage(NearbyStoredFix.choose(null, null, now) == null, "both missing");
    var stale = {"v" => 1, "lat" => -4353100, "lon" => 17263700, "at" => 100};
    Test.assertMessage(NearbyStoredFix.choose(stale, old, now) == old, "both stale");
    Test.assertMessage(!NearbyStoredFix.shouldWrite(old, latest, 9459), "minute limit");
    Test.assertMessage(NearbyStoredFix.shouldWrite(old, latest, now), "older than ten minutes");
    var moved = {"v" => 1, "lat" => -4352000, "lon" => 17263700, "at" => 9900};
    Test.assertMessage(NearbyStoredFix.shouldWrite(old, moved, now), "moved over 100 m");
    old["at"] = 9700;
    Test.assertMessage(!NearbyStoredFix.shouldWrite(old, latest, now), "same place recent fix");
    Test.assertMessage(!NearbyStoredFix.shouldWrite(old, old, now), "do not rewrite same fix");
    Test.assertEqualMessage(-4353100, NearbyStopMaths.toE5(
        (-4353100).toDouble() / 100000.0d), "E5 latitude round trip");
    Test.assertEqualMessage(17263700, NearbyStopMaths.toE5(
        17263700.toDouble() / 100000.0d), "E5 longitude round trip");
    return true;
}
