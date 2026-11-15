import Toybox.Lang;
import Toybox.Test;

(:test, :nearby)
function testNearbyNamesAndDistances(logger as Logger) as Boolean {
    var one = [53090, "Rāpaki Rd near Main Rd", 180] as Array;
    var two = [53091, "Rāpaki Rd near Side Rd", 1200] as Array;
    Test.assertEqualMessage("Rāpaki Rd", NearbyPageNames.clean(one[1] as String), "clean name");
    Test.assertEqualMessage("Rāpaki Rd near Main Rd",
        NearbyPageNames.displayName(one, [one, two] as Array), "collision retains raw name");
    Test.assertEqualMessage("Rāpaki Rd",
        NearbyPageNames.displayName(one, [one] as Array), "unique cleaned name");
    Test.assertEqualMessage("180 m", NearbyPageNames.distance(180), "metres");
    Test.assertEqualMessage("1.2 km", NearbyPageNames.distance(1200), "kilometres");
    Test.assertEqualMessage("0 m", NearbyPageNames.distance(0), "zero");
    Test.assertEqualMessage("99 m", NearbyPageNames.distance(99), "two digits");
    Test.assertEqualMessage("100 m", NearbyPageNames.distance(100), "three digits");
    Test.assertEqualMessage("999 m", NearbyPageNames.distance(999), "metres below threshold");
    Test.assertEqualMessage("1.0 km", NearbyPageNames.distance(1000), "kilometre threshold");
    Test.assertEqualMessage("1.0 km", NearbyPageNames.distance(1049), "round down");
    Test.assertEqualMessage("1.1 km", NearbyPageNames.distance(1050), "round half up");
    Test.assertEqualMessage("3.0 km", NearbyPageNames.distance(2999), "carry to next kilometre");
    Test.assertEqualMessage("3.0 km", NearbyPageNames.distance(3000), "whole kilometres");
    return true;
}
