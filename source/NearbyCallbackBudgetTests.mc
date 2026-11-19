import Toybox.Lang;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Application.Properties;
import Toybox.Time;
import Toybox.Test;

// No Position acquisition, HTTP request or timer callback occurs during the
// measured synchronous cached-tile refresh and display.
(:debug, :nearby)
class NearbyBudgetLocation extends NearbyLocation {
    private var lat as Number = -4350000;
    private var lon as Number = 17260000;
    function getState() as Number { return NearbyLocation.FIX; }
    function getCoordinates() as Array<Number>? { return [lat, lon]; }
    function getFixTime() as Number { return Time.now().value(); }
    function isStale() as Boolean { return false; }
    function refresh() as Void {}
    function moveTo(latE5 as Number, lonE5 as Number) as Void {
        lat = latE5;
        lon = lonE5;
    }
}

(:debug, :nearby)
class BenchDataReader extends ChristchurchBusDataReader {
    var lastRecheck as Number?;
    var recheckCount as Number = 0;
    private var running as Dictionary<Number, Boolean> = {} as Dictionary<Number, Boolean>;

    function getBusData(stopId as Number, handle as Number,
                        callback as Method(data as Dictionary<String, String or Array>?,
                        handle as Number, requestIsCompleted as Boolean,
                        dataIsStale as Boolean) as Void) as Boolean {
        // Exercise the real cache read in the request scheduler, but never
        // start a network request or deliver an asynchronous callback.
        NearbyWorkCount.read();
        ChristchurchBusDataCache.tryGetCachedData(stopId, false);
        return true;
    }

    function recheckBusData(stopId as Number, handle as Number,
                            callback as Method(data as Dictionary<String, String or Array>?,
                            handle as Number, requestIsCompleted as Boolean,
                            dataIsStale as Boolean) as Void) as Boolean {
        lastRecheck = stopId;
        recheckCount++;
        running[stopId] = true;
        return true;
    }

    function isRunning(stopId as Number) as Boolean { return running[stopId] == true; }
    function markRunning(stopId as Number) as Void { running[stopId] = true; }
    function finish(stopId as Number) as Void { running[stopId] = false; }
}

(:test, :nearby)
function testNearbyCachedTileCallbackWorkBudget56Stops(logger as Logger) as Boolean {
    Properties.setValue("nearbyEnabled", false);
    var manager = new ChristchurchBusViewManager([] as Array<Dictionary>);
    Properties.setValue("nearbyEnabled", true);
    Properties.setValue("nearbyStopsToShow", 5);
    var favourites = [] as Array<Dictionary>;
    var rows = [] as Array;
    // The diagnostic formatter emits unknown-zone -00:00. A valid upstream
    // departure response instead supplies an explicit UTC Z suffix.
    var expires = Utils.dateToIsoString(Time.now().add(new Time.Duration(1200)))
        .substring(0, 19) + "Z";
    for (var i = 0; i < 56; i++) {
        var id = 1000 + i;
        rows.add([id, -4350000 + i, 17260000 + i, "Stop" + i] as Array);
        if (i < 16) {
            favourites.add({"stopId" => id, "displayName" => "F" + i} as Dictionary);
        }
        if (i < 24) {
            var visits = [] as Array;
            for (var v = 0; v < 32; v++) {
                visits.add({"PublishedLineName" => "L" + v,
                    "DestinationName" => "Stop" + i + " Destination" + v,
                    "ExpectedDepartureTime" => expires,
                    "VehicleAtStop" => false} as Dictionary);
            }
            Storage.setValue(id, {"ValidUntil" => expires,
                "MonitoredStopVisit" => visits} as PropertyValueType);
            Test.assertMessage(ChristchurchBusDataCache.tryGetCachedData(id, false) != null,
                "busy cache must be readable before measurement");
        }
    }
    var alphabet = "0123456789abcdefghijklmnopqrstuvwxyz";
    var indexes = [] as Array;
    for (var n = 0; n < 56; n++) {
        indexes.add(alphabet.substring(n / 36, n / 36 + 1) +
            alphabet.substring(n % 36, n % 36 + 1));
    }
    var tile = {"v" => 1, "g" => "2026-11-20", "s" => rows,
        "m" => 2, "K" => 56,
        "sh" => "0000000000000000000000000000000000000000000000000000000000000000",
        "i" => indexes, "p" => [] as Array} as Dictionary;
    var tileId = NearbyStopMaths.tileId(-4350000, 17260000);
    Storage.setValue("nearby:" + tileId[0] + "," + tileId[1],
        {"at" => Time.now().value(), "g" => tile["g"], "tile" => tile} as PropertyValueType);
    Storage.setValue("nearby:tiles", [tileId[0] + "," + tileId[1]] as PropertyValueType);
    Test.assertMessage(ChristchurchBusTileReader.validTile(tile), "56-stop tile valid");
    manager.benchSetup(favourites, new NearbyBudgetLocation());
    Toybox.System.println("BENCH START v13");
    manager.manualRefresh();
    Toybox.System.println("BENCH END v13");
    Test.assertEqualMessage(5, manager.benchNearbyCount(), "five nearby pages");
    Test.assertEqualMessage(8, manager.benchCandidateCount(), "eight candidates");
    Test.assertEqualMessage("F0", manager.benchCurrentTitle(), "selected favourite name");
    Test.assertEqualMessage(1, NearbyWorkBudget.tileCallbacks, "one onTile callback");
    Test.assertEqualMessage(1, NearbyWorkBudget.pageRebuilds, "one page rebuild");
    Test.assertEqualMessage(1, NearbyWorkBudget.displayBuilds, "one display build");
    Test.assertMessage(NearbyWorkBudget.reads <= 12, "Storage reads <= 12");
    Test.assertMessage(NearbyWorkBudget.iterations <= 2000, "loop iterations <= 2000");
    Test.assertEqualMessage(0, NearbyWorkBudget.visits, "no visit scan in refresh");
    Test.assertMessage(NearbyWorkBudget.validates <= 1, "tile validations <= 1");
    Test.assertMessage(NearbyWorkBudget.titles <= NearbyWorkBudget.displayBuilds,
        "at most one title lookup per displayed stop");
    Test.assertMessage(NearbyWorkBudget.displayDistances <= NearbyWorkBudget.displayBuilds,
        "at most one distance format per displayed stop");
    // Outside the measured refresh, one existing one-shot timer callback may
    // seed at most one of the old cached responses (32 bounded visits).
    Test.assertEqualMessage(0, manager.benchSeedCursor(), "no synchronous seed");
    manager.onDelayedRefresh();
    Test.assertEqualMessage(1, manager.benchSeedCursor(), "first timer seeds one stop");
    Test.assertMessage(NearbyWorkBudget.visits <= 32, "one 32-visit seed per tick");
    var firstVisits = NearbyWorkBudget.visits;
    manager.onDelayedRefresh();
    Test.assertEqualMessage(2, manager.benchSeedCursor(), "second timer seeds one stop");
    Test.assertMessage(NearbyWorkBudget.visits - firstVisits <= 32,
        "second tick cannot parse multiple cached responses");
    manager.stop();
    return true;
}
