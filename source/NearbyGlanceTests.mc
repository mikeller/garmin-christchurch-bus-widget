import Toybox.Lang;
import Toybox.Test;
import Toybox.Application;
import Toybox.Application.Storage;

(:test, :nearby)
function testNearbyGlanceCache(logger as Logger) as Boolean {
    var previous = Storage.getValue("nearby:last");
    try {
        Storage.deleteValue("nearby:last");
        Test.assertMessage(ChristchurchBusDataCache.getNearbyStop(53090) == null, "missing cache");
        Storage.setValue("nearby:last", {"at" => 1234, "stops" => [
            [53090, "Rāpaki", 120], [53091, "Main", 200]
        ]} as PropertyValueType);
        var selected = ChristchurchBusDataCache.getNearbyStop(53091) as Dictionary;
        Test.assertEqualMessage("Main", selected["displayName"], "selected display name");
        Test.assertEqualMessage("Rāpaki",
            (ChristchurchBusDataCache.getNearbyStop(null) as Dictionary)["displayName"],
            "first cached row for zero favourites");
        Test.assertEqualMessage(53090,
            (ChristchurchBusDataCache.getNearbyStop(null) as Dictionary)["stopId"],
            "first cached row retains its numeric id");
        Test.assertEqualMessage(1234, selected["nearbyAt"], "result timestamp");
        Test.assertMessage(selected["metres"] == null, "no distance");
        Test.assertMessage(ChristchurchBusDataCache.getNearbyStop(99999) == null, "unknown id");
        Storage.setValue("nearby:last", {"at" => 0, "stops" => [[53090, "Rāpaki", 120]]} as PropertyValueType);
        var unknownAge = ChristchurchBusDataCache.getNearbyStop(53090) as Dictionary;
        Test.assertEqualMessage("Rāpaki", unknownAge["displayName"], "unknown-age cached stop");
        Test.assertEqualMessage(0, unknownAge["nearbyAt"], "unknown age retained");
        Storage.setValue("nearby:last", {"at" => -1, "stops" => [[53090, "Rāpaki", 120]]} as PropertyValueType);
        Test.assertMessage(ChristchurchBusDataCache.getNearbyStop(53090) == null, "negative timestamp");
        Storage.setValue("nearby:last", {"at" => 1234, "stops" => [
            [53090, "Rāpaki", 120], [53091, "old shape"]
        ]} as PropertyValueType);
        Test.assertMessage(ChristchurchBusDataCache.getNearbyStop(53090) == null,
            "invalid second row rejects whole result");
        Storage.setValue("nearby:last", {"at" => "old", "stops" => [
            [53090, "Rāpaki", 120]
        ]} as PropertyValueType);
        Test.assertMessage(ChristchurchBusDataCache.getNearbyStop(53090) == null,
            "old timestamp shape");
    } finally {
        if (previous == null) {
            Storage.deleteValue("nearby:last");
        } else {
            Storage.setValue("nearby:last", previous as PropertyValueType);
        }
    }
    Test.assertEqualMessage(" 0m old", NearbyGlanceAge.label(120, 100), "future clock");
    Test.assertEqualMessage(" age unknown", NearbyGlanceAge.label(0, 100),
        "unknown age must not appear to be fresh");
    Test.assertEqualMessage(" 2m old", NearbyGlanceAge.label(120, 240), "minutes");
    Test.assertEqualMessage(" 2h old", NearbyGlanceAge.label(120, 7320), "hours");
    return true;
}
