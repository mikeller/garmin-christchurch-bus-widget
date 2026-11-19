import Toybox.Lang;
import Toybox.Test;

(:debug, :nearby)
class NearbyDepartureCoverageTestData {
    static function data(line as String, destination as String) as Dictionary {
        return {"MonitoredStopVisit" => [
            {"PublishedLineName" => line, "DestinationName" => destination}
        ]} as Dictionary;
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
    var selected = NearbyDepartureCoverage.select(entries, [] as Array, 3);
    Test.assertEqualMessage(3, selected.size(), "three visible pages");
    Test.assertEqualMessage(1001, (selected[0] as Array)[0], "nearest retained");
    Test.assertEqualMessage(1003, (selected[1] as Array)[0], "different destination retained");
    Test.assertEqualMessage(1005, (selected[2] as Array)[0], "unknown retained");
    Test.assertEqualMessage(1, NearbyDepartureCoverage.select(
        [[1002, 4l, shared, false]] as Array,
        [[2001, 4l, shared, true]] as Array, 3).size(), "equal-distance favourite does not cover");
    Test.assertEqualMessage(0, NearbyDepartureCoverage.select(
        [[1002, 4l, shared, false]] as Array,
        [[2001, 1l, shared, true]] as Array, 3).size(), "strictly closer favourite covers");
    Test.assertMessage(NearbyDepartureCoverage.keys(
        {"ErrorCondition" => "No trips on stop.", "MonitoredStopVisit" => [shared]} as Dictionary) == null,
        "errors cannot establish coverage");
    Test.assertMessage(NearbyDepartureCoverage.keys(
        {"MonitoredStopVisit" => [] as Array} as Dictionary) == null,
        "no departures cannot establish coverage");
    return true;
}
