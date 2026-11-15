import Toybox.Lang;
import Toybox.Test;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Time;

(:test, :nearby)
function testLastStopIndexUpgrade(logger as Logger) as Boolean {
    var key = Constants.LAST_STOP_INDEX_NAME;
    var previous = Storage.getValue(key);
    var favourites = [
        {"stopId" => 53090, "displayName" => "First"},
        {"stopId" => 53091, "displayName" => "Second"}
    ] as Array<Dictionary>;
    try {
        Storage.setValue(key, {"stopIndex" => 1} as PropertyValueType);
        Test.assertEqualMessage(53091, ChristchurchBusDataCache.getLastStop(favourites),
            "legacy index maps to stop id");
        Test.assertEqualMessage(53091,
            (Storage.getValue(key) as Dictionary)["stopId"], "upgrade persisted");
        Storage.setValue(key, {"stopIndex" => 5} as PropertyValueType);
        Test.assertMessage(ChristchurchBusDataCache.getLastStop(favourites) == null,
            "invalid legacy index discarded");
        Storage.setValue(key, {"stopId" => 99999} as PropertyValueType);
        Test.assertEqualMessage(99999, ChristchurchBusDataCache.getLastStop(favourites),
            "unknown id left for caller's first-page fallback");
        Storage.setValue(key, {"stopId" => 53091,
            "resetTime" => Time.now().value() - 1} as PropertyValueType);
        Test.assertMessage(ChristchurchBusDataCache.getLastStop(favourites) == null,
            "expired id discarded");
    } finally {
        if (previous == null) {
            Storage.deleteValue(key);
        } else {
            Storage.setValue(key, previous as PropertyValueType);
        }
    }
    return true;
}
