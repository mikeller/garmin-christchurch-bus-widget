import Toybox.Lang;
import Toybox.Test;

(:test)
function testNearbyDepartureScheduling(logger as Logger) as Boolean {
    var one = [[1000, true, 0]] as Array;
    var selected = NearbyDepartureSchedule.choose(one, 0, 8, [] as Array<Number>, true);
    Test.assertEqualMessage(1, selected.size(), "one favourite, no nearby");
    Test.assertEqualMessage(0, selected[0], "stale visible favourite first");

    for (var f = 1; f <= 16; f += f == 1 ? 2 : 13) {
        for (var nearby = 0; nearby <= 5; nearby += nearby == 0 ? 3 : 2) {
            var pages = [] as Array;
            for (var i = 0; i < f; i++) {
                pages.add([1000 + i, true, 0]);
            }
            for (var i = 0; i < nearby; i++) {
                pages.add([2000 + i, false, 0]);
            }
            var cap = 8;
            selected = NearbyDepartureSchedule.choose(pages, 0, cap,
                [] as Array<Number>, true);
            Test.assertEqualMessage(pages.size() < cap ? pages.size() : cap,
                selected.size(), "page count respects cap");
            Test.assertEqualMessage(0, selected[0], "current stale page first");
            for (var i = 0; i < selected.size(); i++) {
                if (i < f && f >= cap) {
                    Test.assertMessage((pages[selected[i]] as Array)[1] == true,
                        "favourites win age ties");
                }
            }
        }
    }

    var pages = [[10, true, 100], [11, true, 100], [12, true, 100],
                 [20, false, 0], [21, false, 0]] as Array;
    selected = NearbyDepartureSchedule.choose(pages, 2, 3, [] as Array<Number>, false);
    Test.assertEqualMessage(3, selected.size(), "cap of three");
    Test.assertEqualMessage(3, selected[0], "older nearby first despite favourite tie preference");
    Test.assertEqualMessage(4, selected[1], "next old nearby in cycling order");
    Test.assertEqualMessage(2, selected[2], "proximity breaks same-age favourite tie");

    selected = NearbyDepartureSchedule.choose(pages, 2, 3, [20] as Array<Number>, true);
    Test.assertEqualMessage(2, selected[0], "stale visible page is requested");
    Test.assertEqualMessage(4, selected[1], "in-flight page excluded");
    for (var i = 0; i < selected.size(); i++) {
        Test.assertMessage(selected[i] != 3, "never request an in-flight stop");
    }
    selected = NearbyDepartureSchedule.choose(pages, 3, 1, [] as Array<Number>, true);
    Test.assertEqualMessage(3, selected[0], "stale nearby page has visible priority");
    selected = NearbyDepartureSchedule.choose(pages, 3, 1, [20] as Array<Number>, true);
    Test.assertEqualMessage(4, selected[0], "in-flight current page not duplicated");

    var staged = [] as Array;
    for (var i = 0; i < 16; i++) {
        staged.add([1000 + i, true, 0]);
    }
    for (var i = 0; i < 5; i++) {
        staged.add([2000 + i, false, 0]);
    }
    for (var cycle = 0; cycle < 3; cycle++) {
        selected = NearbyDepartureSchedule.choose(staged, 0, 8,
            [] as Array<Number>, false);
        for (var i = 0; i < selected.size(); i++) {
            var row = staged[selected[i]] as Array;
            row[2] = cycle + 1;
        }
    }
    for (var i = 0; i < staged.size(); i++) {
        Test.assertMessage((staged[i] as Array)[2] != 0,
            "all 16 favourites and five nearby serviced within three cycles");
    }
    return true;
}
