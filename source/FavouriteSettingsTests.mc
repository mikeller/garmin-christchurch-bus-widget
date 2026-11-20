import Toybox.Lang;
import Toybox.Application;
import Toybox.Application.Properties;
import Toybox.Test;

(:test)
function testFavouriteStopNormalisation(logger as Logger) as Boolean {
    var missing = StoredBusData.normaliseStop({"stopId" => 1000} as Dictionary) as Dictionary;
    Test.assertEqualMessage(1000, missing["stopId"], "lower Number bound");
    Test.assertEqualMessage("", missing["displayName"], "absent optional name");
    Test.assertEqualMessage("", (StoredBusData.normaliseStop(
        {"stopId" => 99999l, "displayName" => null} as Dictionary) as Dictionary)["displayName"],
        "null optional name");
    var longId = StoredBusData.normaliseStop(
        {"stopId" => 53091l, "displayName" => "  ", "extra" => "ignored"} as Dictionary) as Dictionary;
    Test.assertMessage(longId["stopId"] instanceof Number, "Long converted to Number");
    Test.assertEqualMessage(53091, longId["stopId"], "valid Long retained");
    Test.assertEqualMessage("", longId["displayName"], "blank name normalised");
    Test.assertMessage(!longId.hasKey("extra"), "unknown keys ignored");
    Test.assertEqualMessage("", (StoredBusData.normaliseStop(
        {"stopId" => 53092, "displayName" => 4} as Dictionary) as Dictionary)["displayName"],
        "non-String optional name cannot crash a page");
    var longName = "abcdefghijklmnopqrstuvwxyz1234567890";
    var clipped = StoredBusData.normaliseStop(
        {"stopId" => 53093, "displayName" => longName} as Dictionary) as Dictionary;
    Test.assertEqualMessage(32, (clipped["displayName"] as String).length(),
        "long name bounded in memory");
    Test.assertMessage(StoredBusData.normaliseStop(null) == null, "missing entry");
    Test.assertMessage(StoredBusData.normaliseStop([1000] as Array) == null,
        "non-Dictionary entry");
    Test.assertMessage(StoredBusData.normaliseStop({"displayName" => "Missing"} as Dictionary) == null,
        "missing id");
    Test.assertMessage(StoredBusData.normaliseStop(
        {"stopId" => "53091", "displayName" => "Invalid"} as Dictionary) == null,
        "string id");
    Test.assertMessage(StoredBusData.normaliseStop({"stopId" => 999} as Dictionary) == null,
        "below range");
    Test.assertMessage(StoredBusData.normaliseStop({"stopId" => 100000l} as Dictionary) == null,
        "above range as Long");
    Test.assertMessage(StoredBusData.normaliseStop({"stopId" => 2147483648l} as Dictionary) == null,
        "out of Number range rejected before conversion");
    var raw = [] as Array;
    raw.add({"stopId" => 1000, "displayName" => "first"});
    raw.add({"stopId" => 1000, "displayName" => "duplicate"});
    raw.add(["not a dictionary"] as Array);
    for (var i = 1; i <= 18; i++) {
        raw.add({"stopId" => 2000 + i});
    }
    var clean = StoredBusData.normaliseStops(raw);
    Test.assertEqualMessage(16, clean.size(), "only sixteen valid stops in memory");
    Test.assertEqualMessage(1000, clean[0]["stopId"], "first duplicate retained");
    Test.assertEqualMessage(1000, clean[1]["stopId"],
        "existing getStopsProperty path handles duplicate IDs");
    Test.assertEqualMessage(2014, clean[15]["stopId"], "malformed entry did not take a slot");
    return true;
}

(:test)
function testFavouriteSettingsRoundTripDoesNotEraseEntries(logger as Logger) as Boolean {
    var prior = Properties.getValue("stops");
    try {
        var input = [{"stopId" => 53090, "displayName" => "Named"},
                     {"stopId" => 53091},
                     {"stopId" => 53092l, "displayName" => null},
                     {"stopId" => 53093, "displayName" => ""}] as Array;
        Properties.setValue("stops", input as Array<PropertyValueType>);
        var before = Properties.getValue("stops") as Array;
        Test.assertEqualMessage(4, before.size(), "runtime accepted all optional-name shapes");
        var beforeText = before.toString();
        ChristchurchBusAppProperties.resetStopsForTest();
        var loaded = ChristchurchBusAppProperties.loadStops();
        Test.assertEqualMessage(4, loaded.size(), "all valid favourites survive the read");
        for (var i = 0; i < loaded.size(); i++) {
            Test.assertMessage(loaded[i]["stopId"] instanceof Number,
                "page gets Number id");
            Test.assertMessage(loaded[i]["displayName"] instanceof String,
                "page gets String name");
        }
        Test.assertMessage(beforeText.equals((Properties.getValue("stops") as Array).toString()),
            "loadStops must not change persisted Properties");
        Test.assertMessage(!(before[1] as Dictionary).hasKey("displayName"),
            "absent optional name remains absent in Properties");
        // A rejected entry must also survive a later master-style name fill.
        Properties.setValue("stops", [input[0], {"stopId" => 53094, "displayName" => 5}]
            as Array<PropertyValueType>);
        beforeText = (Properties.getValue("stops") as Array).toString();
        ChristchurchBusAppProperties.resetStopsForTest();
        Test.assertEqualMessage(2, ChristchurchBusAppProperties.loadStops().size(),
            "non-String name becomes blank without rejecting the entry");
        ChristchurchBusAppProperties.setStopNameIfEmpty(53094,
            "Long SIRI name beyond thirty-two characters");
        Test.assertMessage(!beforeText.equals(
            (Properties.getValue("stops") as Array).toString()),
            "name fill is an explicit permitted write, not a read-time repair");
        var written = (Properties.getValue("stops") as Array)[1] as Dictionary;
        Test.assertMessage(written["stopId"] instanceof Number, "write retains Number id");
        Test.assertEqualMessage(32, (written["displayName"] as String).length(),
            "SIRI name clipped to settings maximum");
    } finally {
        Properties.setValue("stops", prior instanceof Array ?
            prior as Array<PropertyValueType> : [] as Array<PropertyValueType>);
        ChristchurchBusAppProperties.resetStopsForTest();
    }
    return true;
}

(:test)
function testFavouriteInvalidEntriesNeverRewriteSettings(logger as Logger) as Boolean {
    var prior = Properties.getValue("stops");
    try {
        var input = [{"stopId" => 53090}, {"stopId" => 53090},
                     {"stopId" => "53091"}, {"stopId" => 53092}] as Array;
        Properties.setValue("stops", input as Array<PropertyValueType>);
        var before = (Properties.getValue("stops") as Array).toString();
        ChristchurchBusAppProperties.resetStopsForTest();
        var loaded = ChristchurchBusAppProperties.getStopsProperty();
        Test.assertEqualMessage(2, (loaded as Array).size(),
            "duplicate removed only in memory; invalid id skipped");
        ChristchurchBusAppProperties.setStopNameIfEmpty(53090, "Named");
        Test.assertMessage(before.equals((Properties.getValue("stops") as Array).toString()),
            "rejected entries cannot be lost by duplicate removal or name fill");
        var oversized = [] as Array;
        for (var i = 0; i < 18; i++) {
            oversized.add({"stopId" => 2000 + i, "displayName" => "Stop"} as Dictionary);
        }
        Properties.setValue("stops", oversized as Array<PropertyValueType>);
        ChristchurchBusAppProperties.resetStopsForTest();
        Test.assertEqualMessage(16, ChristchurchBusAppProperties.loadStops().size(),
            "at most sixteen favourites in memory");
        Test.assertEqualMessage(18, (Properties.getValue("stops") as Array).size(),
            "overlong persisted array not truncated by read");
        Properties.setValue("stops", [
            {"stopId" => 53090l, "displayName" => "First"},
            {"stopId" => 53090, "displayName" => "Duplicate"},
            {"stopId" => 53091, "displayName" => ""}
        ] as Array<PropertyValueType>);
        ChristchurchBusAppProperties.resetStopsForTest();
        Test.assertEqualMessage(2, (ChristchurchBusAppProperties.getStopsProperty() as Array).size(),
            "existing duplicate removal still works");
        var afterDuplicate = Properties.getValue("stops") as Array;
        Test.assertEqualMessage(2, afterDuplicate.size(), "only duplicates may be removed on write");
        Test.assertMessage((afterDuplicate[0] as Dictionary)["stopId"] instanceof Number,
            "duplicate write uses Number ids");
        ChristchurchBusAppProperties.setStopNameIfEmpty(53091, "Filled");
        Test.assertEqualMessage("Filled",
            ((Properties.getValue("stops") as Array)[1] as Dictionary)["displayName"],
            "existing blank-name-fill still works");
    } finally {
        Properties.setValue("stops", prior instanceof Array ?
            prior as Array<PropertyValueType> : [] as Array<PropertyValueType>);
        ChristchurchBusAppProperties.resetStopsForTest();
    }
    return true;
}
