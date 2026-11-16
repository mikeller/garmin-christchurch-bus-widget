import Toybox.Lang;
import Toybox.Test;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Application.Properties;
import Toybox.Time;

(:test, :nearby)
function testLastStopIndexUpgrade(logger as Logger) as Boolean {
    var key = Constants.LAST_STOP_INDEX_NAME;
    var previous = Storage.getValue(key);
    var previousSetting = ChristchurchBusAppProperties.getStopResetTimeMin();
    var favourites = [
        {"stopId" => 53090, "displayName" => "First"},
        {"stopId" => 53091, "displayName" => "Second"}
    ] as Array<Dictionary>;
    try {
        // A zero-minute setting means never remember, including old records.
        // Enable remembering explicitly before testing legacy migration.
        Properties.setValue("stopResetTimeMin", -1);
        Storage.setValue(key, {"stopIndex" => 1} as PropertyValueType);
        Test.assertEqualMessage(53091, ChristchurchBusDataCache.getLastStop(favourites),
            "legacy index maps to stop id");
        Test.assertEqualMessage(53091,
            (Storage.getValue(key) as Dictionary)["stopId"], "upgrade persisted");
        Test.assertEqualMessage(53091, ChristchurchBusDataCache.getLastFavourite(favourites),
            "upgraded record survives another restart");
        Storage.setValue(key, {"stopIndex" => 1,
            "resetTime" => Time.now().value() + 300} as PropertyValueType);
        Properties.setValue("stopResetTimeMin", 5);
        Test.assertEqualMessage(53091, ChristchurchBusDataCache.getLastFavourite(favourites),
            "unexpired master record with finite reset");
        Storage.setValue(key, {"stopIndex" => 1l,
            "resetTime" => Time.now().value() + 300} as PropertyValueType);
        Test.assertEqualMessage(53091, ChristchurchBusDataCache.getLastFavourite(favourites),
            "stored Long legacy index maps to favourite");
        Test.assertEqualMessage(53091, ChristchurchBusDataCache.getLastFavourite(favourites),
            "unconverted Long index survives another restart");
        Properties.setValue("stopResetTimeMin", 0);
        Test.assertMessage(ChristchurchBusDataCache.getLastStop(favourites) == null,
            "zero minutes never restores");
        Properties.setValue("stopResetTimeMin", -1);
        Storage.setValue(key, {"stopIndex" => 5} as PropertyValueType);
        Test.assertMessage(ChristchurchBusDataCache.getLastStop(favourites) == null,
            "invalid legacy index discarded");
        Storage.setValue(key, {"stopIndex" => 0} as PropertyValueType);
        Test.assertMessage(ChristchurchBusDataCache.getLastFavourite([] as Array<Dictionary>) == null,
            "empty favourites cannot restore a legacy index");
        Storage.setValue(key, {"stopIndex" => "1"} as PropertyValueType);
        Test.assertMessage(ChristchurchBusDataCache.getLastFavourite(favourites) == null,
            "malformed index discarded");
        Storage.setValue(key, {"stopId" => 99999} as PropertyValueType);
        Test.assertEqualMessage(99999, ChristchurchBusDataCache.getLastStop(favourites),
            "unknown id left for caller's first-page fallback");
        Storage.setValue(key, {"stopId" => 53091,
            "resetTime" => Time.now().value() - 1} as PropertyValueType);
        Test.assertMessage(ChristchurchBusDataCache.getLastStop(favourites) == null,
            "expired id discarded");
    } finally {
        Properties.setValue("stopResetTimeMin", previousSetting);
        if (previous == null) {
            Storage.deleteValue(key);
        } else {
            Storage.setValue(key, previous as PropertyValueType);
        }
    }
    return true;
}
