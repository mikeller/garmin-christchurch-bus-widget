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
    return true;
}
