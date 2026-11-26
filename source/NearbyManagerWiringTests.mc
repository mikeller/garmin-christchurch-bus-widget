import Toybox.Lang;
import Toybox.Application.Properties;
import Toybox.Test;

(:test, :nearby)
class NearbySelectProbe {
    var selected as Number = 0;
    function nextStop() as Void { selected++; }
}

(:test, :nearby)
function testNearbySelectNeedsNoSecondCallback(logger as Logger) as Boolean {
    var probe = new NearbySelectProbe();
    var delegate = new ChristchurchBusBehaviorDelegate(null, probe.method(:nextStop));
    Test.assertMessage(delegate.onSelect(), "Select is handled");
    Test.assertEqualMessage(1, probe.selected, "queued navigation needs no extra callback");
    Test.assertMessage(!delegate.onBack(), "Back is left to the widget stack");
    Test.assertMessage(!delegate.onNextPage(), "Down is left to the widget carousel");
    Test.assertEqualMessage(1, probe.selected, "dismissal inputs never navigate pages");
    return true;
}

(:test, :nearby)
function testEmptyNearbyPayloadKeepsPageAndShowsStatus(logger as Logger) as Boolean {
    var shared = NearbyDepartureCoverageTestData.data("8", "City");
    var empty = {"MonitoredStopVisit" => [] as Array} as Dictionary;
    var stops = NearbyDepartureCoverageTestData.prepare(
        [[1001, 1l, shared, false], [1002, 4l, empty, false],
         [1003, 9l, shared, false]] as Array);
    Test.assertEqualMessage(2, NearbyDepartureCoverage.select(stops, [] as Array, 3).size(),
        "empty nearby stop retained while shared later stop is suppressed");
    Test.assertEqualMessage(1002,
        (NearbyDepartureCoverage.select(stops, [] as Array, 3)[1] as Array)[0],
        "empty stop remains visible");
    Test.assertEqualMessage(Constants.NO_BUSES_STRING,
        ChristchurchBusView.noDepartureMessage(empty["MonitoredStopVisit"] as Array),
        "successful empty payload shows no more buses");
    Test.assertEqualMessage(Constants.NO_INFORMATION_STRING,
        ChristchurchBusView.noDepartureMessage([shared] as Array),
        "unrenderable non-empty payload is not called empty");
    Test.assertMessage(!ChristchurchBusDataReader.hasVisits(empty["MonitoredStopVisit"] as Array),
        "empty response has no visit from which to persist a stop name");
    Test.assertMessage(ChristchurchBusDataReader.hasVisits([shared] as Array),
        "normal response retains stop-name persistence");
    Test.assertEqualMessage(0,
        ((new ChristchurchBusDataReader()).compressData(empty
            as Dictionary<String, String or Array>)["MonitoredStopVisit"] as Array).size(),
        "reader keeps successful zero-visit payload for explicit empty state");
    return true;
}

(:test, :nearby)
function testHiddenFavouriteIgnoresLateCallbacks(logger as Logger) as Boolean {
    Properties.setValue("nearbyEnabled", false);
    var manager = new ChristchurchBusViewManager([] as Array<Dictionary>);
    manager.benchSetup(
        [{"stopId" => 1000, "displayName" => "Favourite"}] as Array<Dictionary>,
        new NearbyBudgetLocation());
    manager.benchSetStarted();
    manager.benchHideCurrentView();
    Test.assertMessage(!manager.benchIsVisible(), "Back hides current favourite");
    manager.onDelayedRefresh();
    manager.onBusDataReady(NearbyDepartureCoverageTestData.data("8", "City"),
        1000, true, false);
    Test.assertMessage(!manager.benchIsVisible(),
        "late refresh and HTTP callback cannot bring the widget back");
    manager.stop();
    return true;
}

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
    Test.assertEqualMessage(1000, manager.benchSelectedStop(),
        "favourite selected before nearby list");
    Test.assertEqualMessage(2, manager.benchNearbyCount(), "two nearby pages");
    var reader = manager.benchReader();
    var shared = {"MonitoredStopVisit" => [
        {"PublishedLineName" => " 8 ", "DestinationName" => " City ",
         "ExpectedDepartureTime" => "2030-11-20T12:00:00Z"}]}
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
        {"PublishedLineName" => "9", "DestinationName" => "Airport",
         "ExpectedDepartureTime" => "2030-11-20T12:00:00Z"}]}
        as Dictionary<String, String or Array>;
    manager.onBusDataReady(distinct, 1001, true, false);
    reader.finish(1001);
    Test.assertMessage(!manager.benchIsDropped(1001),
        "new response restores previously covered candidate");
    Test.assertEqualMessage(1000, manager.benchSelectedStop(),
        "restoring ahead of a full page limit falls back to first favourite");
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
        oversized.add({"PublishedLineName" => "8", "DestinationName" => "City",
            "ExpectedDepartureTime" => "2030-11-20T12:00:00Z"});
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

(:test, :nearby)
function testChangedNearbyListStartsAtFirstPage(logger as Logger) as Boolean {
    Properties.setValue("nearbyEnabled", false);
    var manager = new ChristchurchBusViewManager([] as Array<Dictionary>);
    Properties.setValue("nearbyEnabled", true);
    Properties.setValue("nearbyStopsToShow", 1);
    Properties.setValue("favouritesBeforeNearby", 16);
    var location = new NearbyBudgetLocation();
    manager.benchSetup([{"stopId" => 1000, "displayName" => "First"},
                        {"stopId" => 1001, "displayName" => "Last"}] as Array<Dictionary>,
        location);
    manager.onTile(ChristchurchBusTileReader.READY,
        {"v" => 1, "g" => "2026-11-20",
         "s" => [[1000, -4350000, 17260000, "First"],
                 [1001, -4350000, 17260001, "Last"],
                 [1002, -4350000, 17260002, "Near"]]} as Dictionary, false);
    manager.nextStop();
    manager.nextStop();
    Test.assertEqualMessage(1002, manager.benchSelectedStop(), "selected nearby page");
    manager.onTile(ChristchurchBusTileReader.READY,
        {"v" => 1, "g" => "2026-11-20",
         "s" => [[1000, -4350000, 17260000, "First"],
                 [1001, -4350000, 17260001, "Last"],
                 [1003, -4350000, 17260002, "Replacement"]]} as Dictionary, false);
    Test.assertEqualMessage(1000, manager.benchSelectedStop(),
        "missing nearby page restarts at first favourite, not last before Nearby");
    manager.nextStop();
    Test.assertEqualMessage(1001, manager.benchSelectedStop(),
        "Select continues forward from first page");
    manager.stop();
    return true;
}
