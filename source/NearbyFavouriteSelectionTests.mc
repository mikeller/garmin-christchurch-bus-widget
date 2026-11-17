import Toybox.Lang;
import Toybox.Test;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Application.Properties;

(:test, :nearby)
function testNearbySelectionKeepsLastFavourite(logger as Logger) as Boolean {
    var key = Constants.LAST_STOP_INDEX_NAME;
    var previous = Storage.getValue(key);
    var glance = Storage.getValue(NearbyGlanceStop.KEY);
    var setting = ChristchurchBusAppProperties.getStopResetTimeMin();
    var favourites = [{"stopId" => 53090, "displayName" => "First"},
                      {"stopId" => 53091, "displayName" => "Second"}] as Array<Dictionary>;
    var nearby = [[53092, "Near", 50]] as Array;
    try {
        Properties.setValue("stopResetTimeMin", 65);
        for (var before = 0; before <= 2; before++) {
            Storage.deleteValue(key);
            var ordered = NearbyPageOrder.build([53090, 53091] as Array<Number>,
                nearby, [] as Array, before, NearbyPageOrder.READY);
            // Pick the favourite immediately before the nearby list, so
            // the next Select after restoring enters the nearby list.
            var favouriteIndex = before == 1 ? 0 : before == 0 ? 2 : 1;
            var favouriteId = before == 1 ? 53090 : 53091;
            var index = favouriteIndex;
            var favouritePage = {"stopId" => favouriteId};
            ChristchurchBusDataCache.rememberFavouritePage(favouritePage, favourites);
            NearbyGlanceStop.rememberPage(favouritePage);
            index = NearbyPageOrder.nextIndex(index, ordered.size());
            Test.assertEqualMessage(53092,
                (ordered[index] as Array)[NearbyStopMaths.PAGE_CODE],
                "Select after favourite reaches nearby");
            var nearbyPage = {"stopId" => 53092, "nearby" => true};
            ChristchurchBusDataCache.rememberFavouritePage(nearbyPage, favourites);
            NearbyGlanceStop.rememberPage(nearbyPage);
            Test.assertEqualMessage(53092, NearbyGlanceStop.read()["stopId"],
                "glance tracks displayed nearby stop");
            var restart = ChristchurchBusDataCache.getLastFavourite(favourites);
            if (favouriteId == 53090) {
                Test.assertMessage(restart == null,
                    "first favourite needs no stored restart record");
            } else {
                Test.assertEqualMessage(favouriteId, restart,
                    "restart on nearby keeps last favourite");
            }
            Test.assertEqualMessage(favouriteIndex,
                NearbyPageOrder.selectedIndex(ordered,
                    restart, -1, favouriteIndex),
                "restart returns to last favourite before nearby");
            index = NearbyPageOrder.nextIndex(index, ordered.size());
            while (index != favouriteIndex) {
                var code = (ordered[index] as Array)[NearbyStopMaths.PAGE_CODE] as Number;
                ChristchurchBusDataCache.rememberFavouritePage({"stopId" => code}, favourites);
                var remembered = ChristchurchBusDataCache.getLastFavourite(favourites);
                if (code == 53090) {
                    Test.assertMessage(remembered == null,
                        "first favourite clears the restart record");
                } else {
                    Test.assertEqualMessage(code, remembered,
                        "passing a favourite updates the restart record");
                }
                index = NearbyPageOrder.nextIndex(index, ordered.size());
            }
            ChristchurchBusDataCache.rememberFavouritePage(favouritePage, favourites);
            if (favouriteId == 53090) {
                Test.assertMessage(ChristchurchBusDataCache.getLastFavourite(favourites) == null,
                    "cycling to first favourite leaves no record");
            } else {
                Test.assertEqualMessage(favouriteId,
                    ChristchurchBusDataCache.getLastFavourite(favourites),
                    "cycling back to favourite updates record");
            }
        }
        Storage.deleteValue(key);
        ChristchurchBusDataCache.rememberFavouritePage({"nearbySlot" => true},
            [] as Array<Dictionary>);
        ChristchurchBusDataCache.rememberFavouritePage({"stopId" => 53092,
            "nearby" => true}, [] as Array<Dictionary>);
        Test.assertMessage(Storage.getValue(key) == null,
            "no favourites creates no restart record");
        Properties.setValue("stopResetTimeMin", -1);
        Storage.setValue(key, {"stopIndex" => 1} as PropertyValueType);
        ChristchurchBusDataCache.rememberFavouritePage(
            {"stopId" => 53092, "nearby" => true}, favourites);
        Test.assertEqualMessage(53091, ChristchurchBusDataCache.getLastFavourite(favourites),
            "nearby selection retains legacy upgrade record");
    } finally {
        Properties.setValue("stopResetTimeMin", setting);
        if (previous == null) {
            Storage.deleteValue(key);
        } else {
            Storage.setValue(key, previous as PropertyValueType);
        }
        if (glance == null) {
            Storage.deleteValue(NearbyGlanceStop.KEY);
        } else {
            Storage.setValue(NearbyGlanceStop.KEY, glance as PropertyValueType);
        }
    }
    return true;
}
