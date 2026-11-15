import Toybox.Lang;
import Toybox.Test;

(:test)
function testStoredBusDataUpgradeValidation(logger as Logger) as Boolean {
    var favourites = [{"stopId" => 52927, "displayName" => "Willesden Ave"},
                      {"stopId" => 53185, "displayName" => ""}] as Array<Dictionary>;
    Test.assertMessage(StoredBusData.validStop(favourites[0]), "published stop shape");
    Test.assertMessage(StoredBusData.validStop(favourites[1]), "blank favourite name");
    Test.assertMessage(!StoredBusData.validStop({"stopId" => "52927", "displayName" => "Stop"}),
        "reject string id");
    Test.assertMessage(!StoredBusData.validStop({"stopId" => 52927, "displayName" => null}),
        "reject missing name");
    Test.assertMessage(!StoredBusData.validStop(null), "reject missing stop");
    Test.assertMessage(StoredBusData.validLastStop({"stopIndex" => 1}, favourites),
        "published legacy index");
    Test.assertMessage(StoredBusData.validLastStop({"stopId" => 53185}, favourites),
        "new id");
    Test.assertMessage(!StoredBusData.validLastStop({"stopIndex" => 2}, favourites),
        "out of range legacy index");
    Test.assertMessage(!StoredBusData.validLastStop({"stopId" => "53185"}, favourites),
        "invalid id");
    Test.assertMessage(!StoredBusData.validLastStop({"stopId" => 53185,
        "resetTime" => "later"}, favourites), "invalid expiry");
    Test.assertMessage(!StoredBusData.validLastStop(["stopIndex", 0], favourites),
        "invalid dictionary");
    Test.assertMessage(StoredBusData.validDeparture({
        "ValidUntil" => "2026-11-15T19:31:20+13:00",
        "MonitoredStopVisit" => [{"ExpectedDepartureTime" => "2026-11-15T19:30:00+13:00",
            "VehicleAtStop" => false, "PublishedLineName" => "8",
            "DestinationName" => "Lyttelton"}]
    }), "published departures");
    Test.assertMessage(!StoredBusData.validDeparture({
        "ValidUntil" => "2026-11-15T19:31:20+13:00",
        "MonitoredStopVisit" => [[1, 2, 3]]
    }), "reject old or malformed visits");
    Test.assertMessage(!StoredBusData.validDeparture({"ValidUntil" => 42}),
        "reject invalid expiry shape");
    Test.assertMessage(StoredBusData.validNearbyResult({
        "at" => 1234, "stops" => [[52927, "Willesden Ave", 120]]
    }), "current nearby result");
    Test.assertMessage(!StoredBusData.validNearbyResult({
        "at" => 1234, "stops" => [[52927, "Willesden Ave"]]
    }), "reject obsolete nearby row");
    Test.assertMessage(!StoredBusData.validNearbyResult({
        "at" => "1234", "stops" => []
    }), "reject invalid nearby timestamp");
    return true;
}
