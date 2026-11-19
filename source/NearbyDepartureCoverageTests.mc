import Toybox.Lang;
import Toybox.Test;

(:debug, :nearby)
class NearbyDepartureCoverageTestData {
    static function data(line as String, destination as String) as Dictionary {
        return {"MonitoredStopVisit" => [
            {"PublishedLineName" => line, "DestinationName" => destination}
        ]} as Dictionary;
    }

    static function prepare(raw as Array) as Array {
        var result = [] as Array;
        for (var i = 0; i < raw.size(); i++) {
            var row = raw[i] as Array;
            var entry = [row[0], row[1], null, row[3], null, null,
                {} as Dictionary<String, Boolean>, false] as Array;
            NearbyDepartureCoverage.mergeInto(entry,
                NearbyDepartureCoverage.keys(row[2] as Dictionary?));
            result.add(entry);
        }
        return result;
    }
}

(:test, :nearby)
function testNearbyDepartureCoverage(logger as Logger) as Boolean {
    var shared = NearbyDepartureCoverageTestData.data("8", "City");
    var opposite = NearbyDepartureCoverageTestData.data("8", "Airport");
    var shortTurn = NearbyDepartureCoverageTestData.data("8", "City");
    var entries = [[1001, 1l, shared, false], [1002, 4l, shared, false],
                   [1003, 9l, opposite, false], [1004, 16l, shortTurn, false],
                   [1005, 25l, null, false]] as Array;
    var prepared = NearbyDepartureCoverageTestData.prepare(entries);
    var selected = NearbyDepartureCoverage.select(prepared, [] as Array, 3);
    Test.assertEqualMessage(3, selected.size(), "three visible pages");
    Test.assertEqualMessage(1001, (selected[0] as Array)[0], "nearest retained");
    Test.assertEqualMessage(1003, (selected[1] as Array)[0], "different destination retained");
    Test.assertEqualMessage(1005, (selected[2] as Array)[0], "unknown retained");
    var split = NearbyDepartureCoverage.split(prepared, [] as Array, 3);
    var dropped = split[1] as Array;
    Test.assertEqualMessage(2, dropped.size(), "only examined, covered stops dropped");
    Test.assertEqualMessage(1002, (dropped[0] as Array)[0], "shared departure dropped");
    Test.assertEqualMessage(1004, (dropped[1] as Array)[0], "later covered stop dropped");
    split = NearbyDepartureCoverage.split(NearbyDepartureCoverageTestData.prepare(
        [[1001, 1l, shared, false], [1003, 4l, opposite, false],
         [1002, 9l, shared, false], [1005, 16l, null, false]] as Array),
        [] as Array, 2);
    Test.assertEqualMessage(2, (split[0] as Array).size(), "page limit reached");
    Test.assertEqualMessage(0, (split[1] as Array).size(),
        "unexamined stops beyond page limit are not coverage-dropped");
    split = NearbyDepartureCoverage.split(NearbyDepartureCoverageTestData.prepare(
        [[1001, 1l, shared, false], [1002, 4l, shared, false],
         [1003, 9l, null, false]] as Array), [] as Array, 2);
    Test.assertEqualMessage(1002, ((split[1] as Array)[0] as Array)[0],
        "covered stop before page limit is eligible for recheck");
    Test.assertEqualMessage(1003, ((split[0] as Array)[1] as Array)[0],
        "pending stop stays visible and is not dropped");
    Test.assertEqualMessage(1, NearbyDepartureCoverage.select(
        NearbyDepartureCoverageTestData.prepare([[1002, 4l, shared, false]] as Array),
        NearbyDepartureCoverageTestData.prepare([[2001, 4l, shared, true]] as Array),
        3).size(), "equal-distance favourite does not cover");
    Test.assertEqualMessage(0, NearbyDepartureCoverage.select(
        NearbyDepartureCoverageTestData.prepare([[1002, 4l, shared, false]] as Array),
        NearbyDepartureCoverageTestData.prepare([[2001, 1l, shared, true]] as Array),
        3).size(), "strictly closer favourite covers");
    Test.assertMessage(NearbyDepartureCoverage.keys(
        {"ErrorCondition" => "No trips on stop.", "MonitoredStopVisit" => [shared]} as Dictionary) == null,
        "errors cannot establish coverage");
    Test.assertMessage(NearbyDepartureCoverage.keys(
        {"MonitoredStopVisit" => [] as Array} as Dictionary) == null,
        "no departures cannot establish coverage");
    return true;
}

(:test, :nearby)
function testNearbyBoundedKeysAndMonotonicCoverage(logger as Logger) as Boolean {
    var visits = [] as Array;
    for (var i = 0; i < NearbyDepartureCoverage.MAX_VISITS; i++) {
        visits.add({"PublishedLineName" => "8", "DestinationName" => "Place " + i});
    }
    var data = {"MonitoredStopVisit" => visits} as Dictionary;
    NearbyWorkBudget.begin();
    var first = NearbyDepartureCoverage.keys(data);
    Test.assertEqualMessage(32, (first as Array).size(), "32 unique keys");
    Test.assertEqualMessage(32, NearbyWorkBudget.visits, "bounded first parse");
    visits.add({"PublishedLineName" => "8", "DestinationName" => "Extra"});
    Test.assertMessage(NearbyDepartureCoverage.keys(data) == null, "33 visits unknown");
    Test.assertEqualMessage(32, NearbyWorkBudget.visits,
        "oversized response examined no visits");
    var provider = [2001, 1l, null, true, null, null,
        {} as Dictionary<String, Boolean>, false] as Array;
    NearbyDepartureCoverage.mergeInto(provider,
        NearbyDepartureCoverage.keys(NearbyDepartureCoverageTestData.data("8", "City")));
    Test.assertMessage(!NearbyDepartureCoverage.mergeInto(provider, null),
        "unknown response never revokes history");
    NearbyDepartureCoverage.mergeInto(provider,
        NearbyDepartureCoverage.keys(NearbyDepartureCoverageTestData.data("8", "Airport")));
    Test.assertEqualMessage(2, (provider[2] as Array).size(), "old and new keys accumulated");
    var candidates = NearbyDepartureCoverageTestData.prepare(
        [[1001, 4l, NearbyDepartureCoverageTestData.data("8", "City"), false],
         [1002, 9l, NearbyDepartureCoverageTestData.data("8", "Airport"), false]] as Array);
    Test.assertEqualMessage(0, (NearbyDepartureCoverage.split(candidates, [provider], 2)[0] as Array).size(),
        "later response does not restore previously covered stop");
    var colliding = NearbyDepartureCoverageTestData.prepare(
        [[1003, 16l, NearbyDepartureCoverageTestData.data("8C", "ity"), false]] as Array);
    Test.assertEqualMessage(1, NearbyDepartureCoverage.select(colliding, [provider], 2).size(),
        "length prefix distinguishes joined fields");
    return true;
}

(:test, :nearby)
function testNearbySyntheticSelectionWorkBudget(logger as Logger) as Boolean {
    var rows = [] as Array;
    var favourites = [] as Array<Number>;
    var visits = [] as Array;
    for (var i = 0; i < 32; i++) {
        visits.add({"PublishedLineName" => "8", "DestinationName" => "Stop " + i});
    }
    var data = {"MonitoredStopVisit" => visits} as Dictionary;
    for (var i = 0; i < 56; i++) {
        rows.add([1001 + i, 0, i + 1, "S"]);
        if (i >= 8 && i < 24) {
            favourites.add(1001 + i);
        }
    }
    NearbyWorkBudget.begin();
    var split = NearbyStopMaths.nearestSplit(rows, 0, 0, favourites, 8);
    var candidates = [] as Array;
    var providers = [] as Array;
    var nearest = split[0] as Array;
    for (var i = 0; i < nearest.size(); i++) {
        var entry = nearest[i] as Array;
        var provider = [entry[0], (i + 1).toLong(), null, false,
            entry[1], entry[2], {} as Dictionary<String, Boolean>, false] as Array;
        NearbyDepartureCoverage.mergeInto(provider, NearbyDepartureCoverage.keys(data));
        candidates.add(provider);
    }
    for (var i = 0; i < favourites.size(); i++) {
        var provider = [favourites[i], (i + 9).toLong(), null, true,
            null, null, {} as Dictionary<String, Boolean>, false] as Array;
        NearbyDepartureCoverage.mergeInto(provider, NearbyDepartureCoverage.keys(data));
        providers.add(provider);
    }
    NearbyDepartureCoverage.split(candidates, providers, 5);
    Test.assertMessage(NearbyWorkBudget.visits <= 24 * 32,
        "eight candidates and sixteen favourites parse at most 32 visits each");
    Test.assertMessage(NearbyWorkBudget.iterations <= 2048,
        "bounded synthetic selection and key merge iterations");
    Test.assertMessage(NearbyWorkBudget.distances <= 2 * 56,
        "nearest split calculates no more than two distances per row");
    Test.assertEqualMessage(0, NearbyWorkBudget.reads, "pure test performs no Storage reads");
    Test.assertEqualMessage(0, NearbyWorkBudget.validates, "pure test validates no tile");
    Test.assertEqualMessage(0, NearbyWorkBudget.titles, "pure test performs no title lookup");
    return true;
}

(:test, :nearby)
function testNearbySessionKeyOverflowRestoresStops(logger as Logger) as Boolean {
    var provider = [2001, 1l, null, true, null, null,
        {} as Dictionary<String, Boolean>, false] as Array;
    var candidate = NearbyDepartureCoverageTestData.prepare(
        [[1002, 4l, NearbyDepartureCoverageTestData.data("8", "City"), false]] as Array);
    var initial = NearbyDepartureCoverageTestData.data("8", "City");
    Test.assertMessage(NearbyDepartureCoverage.observe(provider, initial),
        "initial provider key");
    for (var i = 1; i < NearbyDepartureCoverage.MAX_SESSION_KEYS; i++) {
        NearbyDepartureCoverage.observe(provider,
            NearbyDepartureCoverageTestData.data("Line " + i, "Destination " + i));
    }
    Test.assertEqualMessage(32, (provider[2] as Array).size(), "exactly at cap usable");
    Test.assertEqualMessage(0,
        (NearbyDepartureCoverage.split(candidate, [provider], 1)[0] as Array).size(),
        "proven shared candidate initially dropped");
    Test.assertMessage(NearbyDepartureCoverage.observe(provider,
        NearbyDepartureCoverageTestData.data("New", "Terminus")), "33rd distinct key overflows");
    Test.assertMessage(provider[7] == true && provider[2] == null,
        "overflow is unknown, not a truncated covering set");
    Test.assertEqualMessage(1,
        (NearbyDepartureCoverage.split(candidate, [provider], 1)[0] as Array).size(),
        "coverage no longer provable, dropped stop restored");
    Test.assertEqualMessage(0, NearbyPageOrder.preserve(
        {"stopId" => 1002, "nearby" => true},
        [{"stopId" => 1002, "nearby" => true}] as Array<Dictionary>, 0),
        "restoring coverage does not move the viewed nearby page");
    Test.assertEqualMessage(0, (provider[6] as Dictionary).size(), "old keys released");
    Test.assertMessage(!NearbyDepartureCoverage.observe(provider, initial),
        "overflow stays unknown until movement resets session");
    var moved = [2001, 1l, null, true, null, null,
        {} as Dictionary<String, Boolean>, false] as Array;
    Test.assertMessage(NearbyDepartureCoverage.observe(moved, initial),
        "new movement session accepts fresh bounded keys");
    Test.assertEqualMessage(0,
        (NearbyDepartureCoverage.split(candidate, [moved], 1)[0] as Array).size(),
        "new session may prove coverage again");
    var large = [] as Array;
    for (var i = 0; i <= NearbyDepartureCoverage.MAX_VISITS; i++) {
        large.add({"PublishedLineName" => "8", "DestinationName" => "City"});
    }
    Test.assertMessage(NearbyDepartureCoverage.observe(moved,
        {"MonitoredStopVisit" => large} as Dictionary), "oversized response overflows");
    Test.assertEqualMessage(1,
        (NearbyDepartureCoverage.split(candidate, [moved], 1)[0] as Array).size(),
        "oversized response cannot suppress with previously cached keys");
    Test.assertMessage(moved[2] == null && moved[7] == true,
        "oversized response invalidates even previously observed provider keys");
    var malformed = [2002, 1l, null, true, null, null,
        {} as Dictionary<String, Boolean>, false] as Array;
    Test.assertMessage(!NearbyDepartureCoverage.observe(malformed,
        {"MonitoredStopVisit" => [
            {"PublishedLineName" => "8", "DestinationName" => 12}
        ]} as Dictionary), "malformed visit cannot establish a key");
    Test.assertMessage(malformed[2] == null,
        "malformed response remains unknown, never an empty covering set");
    Test.assertEqualMessage(1,
        (NearbyDepartureCoverage.split(candidate, [malformed], 1)[0] as Array).size(),
        "malformed provider cannot suppress the matching stop");
    var onlyOversized = [2003, 1l, null, true, null, null,
        {} as Dictionary<String, Boolean>, false] as Array;
    Test.assertMessage(NearbyDepartureCoverage.observe(onlyOversized,
        {"MonitoredStopVisit" => large} as Dictionary), "oversized fresh provider invalidated");
    Test.assertEqualMessage(1,
        (NearbyDepartureCoverage.split(candidate, [onlyOversized], 1)[0] as Array).size(),
        "33-visit provider cannot suppress without any earlier keys");
    return true;
}

(:test, :nearby)
function testCoverageDroppedRecheckAndPageIdentity(logger as Logger) as Boolean {
    var shared = NearbyDepartureCoverageTestData.data("8", "City");
    var unique = NearbyDepartureCoverageTestData.data("9", "Airport");
    var entries = NearbyDepartureCoverageTestData.prepare(
        [[1001, 1l, shared, false], [1002, 4l, shared, false],
         [1003, 9l, unique, false], [1004, 16l, shared, false]] as Array);
    var split = NearbyDepartureCoverage.split(entries, [] as Array, 2);
    var selected = split[0] as Array;
    var dropped = split[1] as Array;
    Test.assertEqualMessage(2, selected.size(), "two pages fill the limit");
    Test.assertEqualMessage(1001, (selected[0] as Array)[0], "first page");
    Test.assertEqualMessage(1003, (selected[1] as Array)[0], "second page");
    Test.assertEqualMessage(1, dropped.size(), "only examined covered stop");
    Test.assertEqualMessage(1002, (dropped[0] as Array)[0],
        "unexamined fourth stop must not enter recheck set");
    var oldPage = {"stopId" => 1003, "nearby" => true};
    var pages = [{"stopId" => 1001, "nearby" => true},
                 {"stopId" => 1003, "nearby" => true}] as Array<Dictionary>;
    Test.assertEqualMessage(1, NearbyPageOrder.preserve(oldPage, pages, 0),
        "selected page initially second");
    Test.assertMessage(!NearbyRecheckPolicy.eligible(false, true, false, 0,
        false, false, null, 200), "timer/update cannot recheck a dropped stop");
    Test.assertMessage(NearbyRecheckPolicy.eligible(true, true, false, 0,
        false, false, 70, 200), "navigation may recheck an eligible dropped stop");
    Test.assertMessage(!NearbyRecheckPolicy.eligible(true, true, false, 0,
        false, false, 100, 200), "recently checked dropped stop is not eligible");
    // Once that dropped stop has new unique departures, its page is inserted
    // ahead of the selected page. Selection remains tied to the stop code.
    Test.assertMessage(NearbyDepartureCoverage.observe(entries[1] as Array,
        NearbyDepartureCoverageTestData.data("10", "Harbour")),
        "rechecked stop gains a distinct departure");
    split = NearbyDepartureCoverage.split(entries, [] as Array, 3);
    selected = split[0] as Array;
    Test.assertEqualMessage(3, selected.size(), "restored page joins the list");
    Test.assertEqualMessage(1002, (selected[1] as Array)[0], "restored before selected");
    pages = [{"stopId" => 1001, "nearby" => true},
             {"stopId" => 1002, "nearby" => true},
             {"stopId" => 1003, "nearby" => true}] as Array<Dictionary>;
    var index = NearbyPageOrder.preserve(oldPage, pages, 0);
    Test.assertEqualMessage(2, index, "selected index follows its stop");
    Test.assertEqualMessage(1003, pages[index]["stopId"], "selected stop unchanged");
    return true;
}
