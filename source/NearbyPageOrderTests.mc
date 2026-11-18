import Toybox.Lang;
import Toybox.Test;

(:test, :nearby)
class NearbyPageOrderTestPages {
    static function fromOrder(ordered as Array) as Array<Dictionary> {
        var pages = [] as Array<Dictionary>;
        for (var i = 0; i < ordered.size(); i++) {
            var row = ordered[i] as Array;
            var code = row[NearbyStopMaths.PAGE_CODE] as Number?;
            pages.add(code == null ? {"nearbySlot" => true} :
                {"stopId" => code, "nearby" => row[NearbyStopMaths.PAGE_IS_FAVOURITE] == false});
        }
        return pages;
    }
}

(:test, :nearby)
function testPageIdentityTransitions(logger as Logger) as Boolean {
    var fav = [101, 102] as Array<Number>;
    var nearA = [[201, "A", 50], [202, "B", 60]] as Array;
    var nearB = [[202, "B", 30], [201, "A", 70]] as Array;
    for (var before = 0; before <= 16; before += before == 2 ? 14 : 1) {
        var empty = NearbyPageOrderTestPages.fromOrder(NearbyPageOrder.build(
            fav, [] as Array, [] as Array, before, NearbyPageOrder.LOCATING));
        var ready = NearbyPageOrderTestPages.fromOrder(NearbyPageOrder.build(
            fav, nearA, [] as Array, before, NearbyPageOrder.READY));
        var reordered = NearbyPageOrderTestPages.fromOrder(NearbyPageOrder.build(
            fav, nearB, [] as Array, before, NearbyPageOrder.READY));
        var waiting = NearbyPageOrderTestPages.fromOrder(NearbyPageOrder.build(
            fav, [] as Array, [] as Array, before, NearbyPageOrder.WAITING_TILE));
        var slotIndex = NearbyPageOrder.preserve({"nearbySlot" => true}, empty, 0);
        Test.assertEqualMessage(slotIndex, NearbyPageOrder.preserve(
            {"nearbySlot" => true}, waiting, 0), "slot survives pending tile");
        Test.assertEqualMessage(slotIndex, NearbyPageOrder.preserve(
            {"nearbySlot" => true}, ready, 0), "slot becomes first nearby");
        for (var f = 0; f < fav.size(); f++) {
            var chosen = {"stopId" => fav[f]};
            var index = NearbyPageOrder.preserve(chosen, ready, 0);
            Test.assertEqualMessage(fav[f], ready[index]["stopId"],
                "favourite survives insertion, including before 16");
            var again = NearbyPageOrder.preserve(chosen, reordered, 0);
            Test.assertEqualMessage(fav[f], reordered[again]["stopId"],
                "favourite survives nearest reorder");
        }
        var nearIndex = NearbyPageOrder.preserve({"stopId" => 201, "nearby" => true},
            reordered, 0);
        Test.assertEqualMessage(201, reordered[nearIndex]["stopId"],
            "nearby page survives reorder");
        Test.assertEqualMessage(nearIndex, NearbyPageOrder.preserve(
            {"stopId" => 201, "nearby" => true}, reordered, 0),
            "repeated updates do not move selected page");
        Test.assertEqualMessage(-1, NearbyPageOrder.preserve(
            {"stopId" => 201, "nearby" => true}, waiting, 0),
            "missing nearby page must be retained until Select");
        var chosenAfterDrop = {"stopId" => fav[0]};
        Test.assertEqualMessage(1, NearbyPageOrder.preserve(chosenAfterDrop,
            NearbyPageOrderTestPages.fromOrder(NearbyPageOrder.build(fav,
                [] as Array, [] as Array, 0, NearbyPageOrder.EMPTY)), 1),
            "after leaving retained page, recompute chosen index by identity");
    }
    var onlySlot = NearbyPageOrderTestPages.fromOrder(NearbyPageOrder.build(
        [] as Array<Number>, [] as Array, [] as Array, 0, NearbyPageOrder.WAITING_TILE));
    Test.assertEqualMessage(0, NearbyPageOrder.preserve(
        {"nearbySlot" => true}, onlySlot, 0), "no favourites keeps status slot");
    return true;
}

(:test, :nearby)
function testNearbySlotPageOrder(logger as Logger) as Boolean {
    var nearby = [[200, "Nearby", 100], [201, "Other", 200]] as Array;
    var favourites = [100, 101, 102] as Array<Number>;
    var states = [NearbyPageOrder.LOCATING, NearbyPageOrder.UNAVAILABLE,
                  NearbyPageOrder.EMPTY];
    for (var s = 0; s < states.size(); s++) {
        for (var size = 0; size < 3; size++) {
            var count = size == 0 ? 0 : size == 1 ? 1 : 3;
            var fav = [] as Array<Number>;
            for (var i = 0; i < count; i++) {
                fav.add(favourites[i]);
            }
            for (var n = 0; n < 4; n++) {
                var before = n == 3 ? 16 : n;
                var order = NearbyPageOrder.build(fav, [] as Array, [] as Array, before, states[s]);
                var slot = before < count ? before : count;
                Test.assertEqualMessage(count + 1, order.size(), "slot plus favourites");
                Test.assertMessage((order[slot] as Array)[NearbyStopMaths.PAGE_CODE] == null,
                    "slot at configured position");
                Test.assertEqualMessage(count > 0 && slot == 0 ? 1 : 0,
                    NearbyPageOrder.initialIndex(order, count, before), "open favourite if slot first");
            }
        }
    }
    for (var n = 0; n < 4; n++) {
        var before = n == 0 ? 0 : n == 1 ? 1 : n == 2 ? 2 : 16;
        var pending = NearbyPageOrder.build(favourites, [] as Array, [] as Array,
            before, NearbyPageOrder.LOCATING);
        var ready = NearbyPageOrder.build(favourites, nearby, [] as Array,
            before, NearbyPageOrder.READY);
        var at = before < 3 ? before : 3;
        Test.assertEqualMessage(5, ready.size(), "two nearby replace slot");
        Test.assertEqualMessage(200, (ready[at] as Array)[NearbyStopMaths.PAGE_CODE],
            "first nearby at slot");
        Test.assertEqualMessage(at, NearbyPageOrder.preserve({"nearbySlot" => true},
            NearbyPageOrderTestPages.fromOrder(ready), 0),
            "slot stays on its replacement");
        var selectedFavourite = at < 3 ? 100 + at : 102;
        Test.assertEqualMessage(at < 3 ? at + 2 : 2,
            NearbyPageOrder.preserve({"stopId" => selectedFavourite},
                NearbyPageOrderTestPages.fromOrder(ready), 0), "favourite retains selection across insertion");
        Test.assertEqualMessage(4, pending.size(), "pending slot count");
    }
    var onlySlot = NearbyPageOrder.build([] as Array<Number>, [] as Array,
        [] as Array, 0, NearbyPageOrder.EMPTY);
    Test.assertEqualMessage(1, onlySlot.size(), "zero favourites still has a slot");
    var one = [100] as Array<Number>;
    var single = NearbyPageOrder.build(one, [] as Array, [] as Array, 1,
        NearbyPageOrder.UNAVAILABLE);
    Test.assertEqualMessage(100, (single[0] as Array)[NearbyStopMaths.PAGE_CODE],
        "one favourite before slot");
    var waiting = NearbyPageOrder.build(one, [] as Array, [] as Array, 0,
        NearbyPageOrder.WAITING_TILE);
    Test.assertEqualMessage(2, waiting.size(), "waiting tile retains slot");
    Test.assertEqualMessage(100, (waiting[1] as Array)[NearbyStopMaths.PAGE_CODE],
        "favourite remains visible during tile load");
    Test.assertEqualMessage(1, NearbyPageOrder.build([] as Array<Number>,
        [] as Array, [] as Array, 0, NearbyPageOrder.WAITING_TILE).size(),
        "without favourites loading retains slot");
    return true;
}

(:test, :nearby)
function testSingleFavouriteSlotAndSelect(logger as Logger) as Boolean {
    var favourite = [3003] as Array<Number>;
    var counts = [0, 1, 3] as Array<Number>;
    for (var before = 0; before <= 2; before++) {
        var locating = NearbyPageOrder.build(favourite, [] as Array, [] as Array,
            before, NearbyPageOrder.LOCATING);
        Test.assertEqualMessage(2, locating.size(), "one favourite and one locating slot");
        var first = NearbyPageOrder.initialIndex(locating, 1, before);
        Test.assertEqualMessage(before == 0 ? 1 : 0, first, "open on favourite");
        Test.assertEqualMessage(3003, (locating[first] as Array)[NearbyStopMaths.PAGE_CODE],
            "favourite not dropped while locating");
        Test.assertEqualMessage(1 - first, NearbyPageOrder.nextIndex(first, 2),
            "Select opens slot");
        Test.assertEqualMessage(first, NearbyPageOrder.nextIndex(1 - first, 2),
            "Select wraps back to favourite");
        for (var i = 0; i < counts.size(); i++) {
            var n = counts[i];
            var split = NearbyStopMaths.nearestSplit(NearbyStopMathsTestData.vectorStops(),
                -4353000, 17263000, favourite, n);
            var ordered = NearbyPageOrder.build(favourite, split[0] as Array,
                split[1] as Array, before,
                n == 0 ? NearbyPageOrder.EMPTY : NearbyPageOrder.READY);
            var expectedSize = n == 0 ? 2 : n + 1;
            Test.assertEqualMessage(expectedSize, ordered.size(), "nearby plus favourite");
            var selected = NearbyPageOrder.preserve({"stopId" => 3003},
                NearbyPageOrderTestPages.fromOrder(ordered), first);
            Test.assertEqualMessage(3003,
                (ordered[selected] as Array)[NearbyStopMaths.PAGE_CODE],
                "keep selected favourite when nearby pages arrive");
            var next = selected;
            for (var step = 0; step < expectedSize; step++) {
                next = NearbyPageOrder.nextIndex(next, expectedSize);
            }
            Test.assertEqualMessage(selected, next, "Select cycles all pages and wraps");
            if (n == 0) {
                Test.assertMessage((ordered[selected] as Array)[NearbyStopMaths.PAGE_METRES] == null,
                    "no distance without a tile");
            } else {
                Test.assertEqualMessage(111,
                    (ordered[selected] as Array)[NearbyStopMaths.PAGE_METRES],
                    "favourite among nearest");
            }
        }
    }
    return true;
}
