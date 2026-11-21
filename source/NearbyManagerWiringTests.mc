import Toybox.Lang;
import Toybox.Application.Properties;
import Toybox.Test;

// Exercise the manager's real response, page-preservation and navigation
// callbacks with a fake reader; neither HTTP nor a timer tick is required.
(:test, :nearby)
function testNearbyManagerResponseAndRecheckWiring(logger as Logger) as Boolean {
    Properties.setValue("nearbyEnabled", false);
    var manager = new ChristchurchBusViewManager([] as Array<Dictionary>);
    Properties.setValue("nearbyEnabled", true);
    Properties.setValue("nearbyStopsToShow", 2);
    Properties.setValue("favouritesBeforeNearby", 1);
    var location = new NearbyBudgetLocation();
    manager.benchSetup([{"stopId" => 1000, "displayName" => "F0"}] as Array<Dictionary>,
        location);
    var rows = [[1000, -4350000, 17260000, "Favourite"],
                [1001, -4349998, 17260000, "A"],
                [1002, -4349996, 17260000, "B"],
                [1003, -4349994, 17260000, "C"]] as Array;
    var tile = {"v" => 1, "g" => "2026-11-20", "s" => rows} as Dictionary;
    manager.onTile(ChristchurchBusTileReader.READY, tile, false);
    manager.benchEnableRetention();
    Test.assertEqualMessage(1000, manager.benchSelectedStop(),
        "favourite selected before nearby list");
    Test.assertEqualMessage(2, manager.benchNearbyCount(), "two nearby pages");
    var reader = manager.benchReader();
    var shared = {"MonitoredStopVisit" => [
        {"PublishedLineName" => " 8 ", "DestinationName" => " City "}]}
        as Dictionary<String, String or Array>;
    reader.markRunning(1000);
    manager.onBusDataReady(shared, 1000, true, false);
    reader.finish(1000);
    reader.markRunning(1001);
    manager.onBusDataReady(shared, 1001, true, false);
    reader.finish(1001);
    Test.assertMessage(manager.benchIsDropped(1001),
        "closer favourite covers candidate after its response arrives");
    Test.assertEqualMessage(1000, manager.benchSelectedStop(),
        "response-driven rebuild preserves viewed favourite");
    manager.benchSetRecheckAge(1001, 121);
    manager.benchStartNewRequestCycle();
    manager.nextStop();
    Test.assertEqualMessage(1002, manager.benchSelectedStop(),
        "navigation enters nearby list");
    Test.assertEqualMessage(0, reader.recheckCount,
        "Select must not issue a request synchronously");
    manager.onDelayedRefresh();
    Test.assertEqualMessage(1001, reader.lastRecheck,
        "only coverage-dropped stop gets rechecked on entry");
    Test.assertEqualMessage(1, reader.recheckCount, "one recheck in flight");
    manager.nextStop();
    Test.assertEqualMessage(1003, manager.benchSelectedStop(),
        "navigation continues within nearby list");
    Test.assertEqualMessage(1, reader.recheckCount,
        "navigation cannot start a second recheck while one is in flight");
    var distinct = {"MonitoredStopVisit" => [
        {"PublishedLineName" => "9", "DestinationName" => "Airport"}]}
        as Dictionary<String, String or Array>;
    manager.onBusDataReady(distinct, 1001, true, false);
    reader.finish(1001);
    Test.assertMessage(!manager.benchIsDropped(1001),
        "new response restores previously covered candidate");
    Test.assertEqualMessage(1003, manager.benchSelectedStop(),
        "restoration keeps the viewed nearby page, even when retained");
    Test.assertEqualMessage(2,
        ((manager.benchCandidateState(1001) as Array)[2] as Array).size(),
        "responses accumulate keys once, rather than replaying cache visits");
    location.moveTo(-4349990, 17260000);
    manager.onTile(ChristchurchBusTileReader.READY, tile, false);
    Test.assertMessage((manager.benchCandidateState(1001) as Array)[2] == null,
        "movement starts a fresh unknown coverage session");
    Test.assertMessage(!manager.benchIsDropped(1001),
        "no old key can suppress a stop after movement");
    var oversized = [] as Array;
    for (var i = 0; i <= NearbyDepartureCoverage.MAX_VISITS; i++) {
        oversized.add({"PublishedLineName" => "8", "DestinationName" => "City"});
    }
    reader.markRunning(1001);
    manager.onBusDataReady({"MonitoredStopVisit" => oversized}
        as Dictionary<String, String or Array>, 1001, true, false);
    reader.finish(1001);
    var state = manager.benchCandidateState(1001) as Array;
    Test.assertMessage(state[7] == true && state[2] == null,
        "oversized response makes this stop's session coverage unknown");
    Test.assertMessage(!manager.benchIsDropped(1001),
        "unknown oversized response cannot drop the stop");
    manager.stop();
    return true;
}
