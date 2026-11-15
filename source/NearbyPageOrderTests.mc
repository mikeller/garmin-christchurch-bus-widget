import Toybox.Lang;
import Toybox.Test;

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
        Test.assertEqualMessage(at, NearbyPageOrder.selectedIndex(ready, null, at, 0),
            "slot stays on its replacement");
        var selectedFavourite = at < 3 ? 100 + at : 102;
        Test.assertEqualMessage(at < 3 ? at + 2 : 2,
            NearbyPageOrder.selectedIndex(ready, selectedFavourite,
                at < 3 ? at + 1 : 2, 0), "favourite retains selection across insertion");
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
    Test.assertEqualMessage(1, waiting.size(),
        "position exists: only favourite, no locating slot while tile loads");
    Test.assertEqualMessage(100, (waiting[0] as Array)[NearbyStopMaths.PAGE_CODE],
        "favourite remains visible during tile load");
    Test.assertEqualMessage(0, NearbyPageOrder.build([] as Array<Number>,
        [] as Array, [] as Array, 0, NearbyPageOrder.WAITING_TILE).size(),
        "without favourites loading is a standalone view, not a page slot");
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
            var selected = NearbyPageOrder.selectedIndex(ordered, 3003, first, first);
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
