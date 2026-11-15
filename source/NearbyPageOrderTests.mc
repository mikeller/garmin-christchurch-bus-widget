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
    return true;
}
