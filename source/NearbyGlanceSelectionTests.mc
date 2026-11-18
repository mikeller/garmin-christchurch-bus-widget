import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

(:test, :nearby)
function testNearbyGlanceSelection(logger as Logger) as Boolean {
    var favourites = [{"stopId" => 53090, "displayName" => "First"},
                      {"stopId" => 53091, "displayName" => "Last"}] as Array<Dictionary>;
    var cached = {"stopId" => 53092, "displayName" => "Nearby", "nearbyAt" => 120};
    var now = 1000;
    var remembered = NearbyFavouriteMemory.restore(
        {"stopId" => 53091, "resetTime" => 1300}, favourites, 5, now);
    Test.assertEqualMessage("Last",
        (NearbyGlanceSelection.select(favourites, remembered, cached) as Dictionary)["displayName"],
        "unexpired remembered favourite matches widget startup");
    var expired = NearbyFavouriteMemory.restore(
        {"stopId" => 53091, "resetTime" => 1000}, favourites, 5, now);
    Test.assertEqualMessage("First",
        (NearbyGlanceSelection.select(favourites, expired, cached) as Dictionary)["displayName"],
        "expired record falls back to first favourite");
    var legacy = NearbyFavouriteMemory.restore(
        {"stopIndex" => 1l}, favourites, -1, now);
    Test.assertEqualMessage("Last",
        (NearbyGlanceSelection.select(favourites, legacy, cached) as Dictionary)["displayName"],
        "legacy Long index matches widget startup");
    var absent = NearbyFavouriteMemory.restore(null, favourites, -1, now);
    Test.assertEqualMessage("First",
        (NearbyGlanceSelection.select(favourites, absent, cached) as Dictionary)["displayName"],
        "no record falls back to first favourite");
    var empty = [] as Array<Dictionary>;
    var selected = NearbyGlanceSelection.select(empty, null, cached) as Dictionary;
    Test.assertEqualMessage(53092, selected["stopId"],
        "no favourites keeps numeric id of first cached nearby row");
    Test.assertMessage(selected["metres"] == null,
        "cached nearby row has no distance");
    Test.assertMessage(NearbyGlanceSelection.select(empty, null, null) == null,
        "no favourites and no cached rows shows no stop");
    return true;
}

(:test, :noNearby)
function testExcludedGlanceFavouriteSelection(logger as Logger) as Boolean {
    // The :glance annotation scopes linked glance code, but the SDK still
    // discovers this :test function on older widgets without a glance.
    if (!(WatchUi has :GlanceView)) {
        return true;
    }
    Test.assertMessage(!ChristchurchBusAppProperties.nearbyEnabled(),
        "excluded glance never reads the absent nearby setting");
    Test.assertMessage(getApp().getGlanceView()[0] instanceof ChristchurchBusGlanceView,
        "favourite-only glance constructs safely");
    return true;
}
