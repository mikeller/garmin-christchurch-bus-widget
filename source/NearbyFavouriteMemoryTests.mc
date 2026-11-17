import Toybox.Lang;
import Toybox.Test;

(:test, :nearby)
function testNearbyFavouriteMemory(logger as Logger) as Boolean {
    var favourites = [{"stopId" => 52927, "displayName" => "First"},
                      {"stopId" => 53185, "displayName" => "Second"}] as Array<Dictionary>;
    Test.assertEqualMessage(53185, NearbyFavouriteMemory.selectedFavourite(
        {"stopId" => 53185}, favourites), "remember favourite");
    Test.assertMessage(NearbyFavouriteMemory.selectedFavourite(
        {"stopId" => 53185, "nearby" => true}, favourites) == null, "not nearby");
    Test.assertMessage(NearbyFavouriteMemory.selectedFavourite(
        {"stopId" => 53000}, favourites) == null, "not unknown");
    var saved = {"stopId" => 53185, "resetTime" => 1300};
    Test.assertEqualMessage(53185, NearbyFavouriteMemory.restore(saved, favourites, 5, 1000),
        "new record");
    Test.assertMessage(NearbyFavouriteMemory.restore(saved, favourites, 0, 1000) == null,
        "disabled");
    Test.assertEqualMessage(53185, NearbyFavouriteMemory.restore(saved, favourites, -1, 1000),
        "enabled with expiry");
    Test.assertEqualMessage(53185, NearbyFavouriteMemory.restore(saved, favourites, 5, 1299),
        "4:59");
    Test.assertMessage(NearbyFavouriteMemory.restore(saved, favourites, 5, 1300) == null,
        "5:00");
    Test.assertMessage(NearbyFavouriteMemory.restore(saved, favourites, 5, 1301) == null,
        "5:01");
    Test.assertEqualMessage(53185, NearbyFavouriteMemory.restore({"stopId" => 53185},
        favourites, -1, 1000), "until changed");
    Test.assertMessage(NearbyFavouriteMemory.restore({"stopId" => 53000},
        favourites, -1, 1000) == null, "unknown id");
    Test.assertEqualMessage(53185, NearbyFavouriteMemory.restore({"stopIndex" => 1},
        favourites, -1, 1000), "legacy index");
    Test.assertEqualMessage(53185, NearbyFavouriteMemory.restore({"stopIndex" => 1l},
        favourites, -1, 1000), "legacy Long index");
    Test.assertMessage(NearbyFavouriteMemory.restore({"stopIndex" => 2l},
        favourites, -1, 1000) == null, "Long index out of range");
    Test.assertMessage(NearbyFavouriteMemory.restore({"stopIndex" => 0l},
        [] as Array<Dictionary>, -1, 1000) == null, "empty favourites");
    Test.assertMessage(NearbyFavouriteMemory.restore({"stopIndex" => 1l,
        "resetTime" => 999}, favourites, 5, 1000) == null, "expired legacy Long");
    Test.assertMessage(NearbyFavouriteMemory.restore({"stopIndex" => 1l},
        favourites, 0, 1000) == null, "disabled legacy Long");
    Test.assertMessage(NearbyFavouriteMemory.restore({"stopIndex" => 1l,
        "resetTime" => "bad"}, favourites, -1, 1000) == null, "malformed legacy Long");
    Test.assertEqualMessage(NearbyFavouriteMemory.RESTORED,
        NearbyFavouriteMemory.restoreReason({"stopId" => 53185}, favourites, 65, 1000),
        "debug restored");
    Test.assertEqualMessage(NearbyFavouriteMemory.EXPIRED,
        NearbyFavouriteMemory.restoreReason({"stopId" => 53185, "resetTime" => 1000},
            favourites, 65, 1000), "debug expired at boundary");
    Test.assertEqualMessage(NearbyFavouriteMemory.NO_RECORD,
        NearbyFavouriteMemory.restoreReason(null, favourites, 65, 1000),
        "debug no record");
    Test.assertEqualMessage(NearbyFavouriteMemory.OUT_OF_RANGE,
        NearbyFavouriteMemory.restoreReason({"stopIndex" => 3}, favourites, 65, 1000),
        "debug out of range");
    Test.assertEqualMessage(NearbyFavouriteMemory.OUT_OF_RANGE,
        NearbyFavouriteMemory.restoreReason({"stopId" => 99999}, favourites, 65, 1000),
        "debug id not a favourite");
    Test.assertEqualMessage(NearbyFavouriteMemory.INVALID,
        NearbyFavouriteMemory.restoreReason({"stopId" => "bad"}, favourites, 65, 1000),
        "debug malformed");
    Test.assertEqualMessage(NearbyFavouriteMemory.INVALID,
        NearbyFavouriteMemory.restoreReason({"stopId" => 2}, favourites, 65, 1000),
        "debug malformed id");
    Test.assertEqualMessage(NearbyFavouriteMemory.DISABLED,
        NearbyFavouriteMemory.restoreReason({"stopId" => 53185}, favourites, 0, 1000),
        "debug disabled");
    var ordered = [[null, null, null, false], [52927, null, null, true],
                   [53000, null, null, false], [53185, null, null, true]] as Array;
    Test.assertEqualMessage(3, NearbyPageOrder.selectedIndex(ordered, 53185, -1, 1),
        "restore after slot and nearby page insertion");
    return true;
}
