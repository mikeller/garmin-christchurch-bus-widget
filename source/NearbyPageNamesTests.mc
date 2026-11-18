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
    var tile = [
        [38197, -4353000, 17263000, "Hereford St near Montreal St"],
        [38198, -4353001, 17263001, "Hereford St near Cambridge Tce"],
        [52927, -4353002, 17263002, "Rolleston Ave near Gloucester St"]
    ] as Array;
    var fallback = "Stop $1$";
    Test.assertEqualMessage("Configured name",
        NearbyPageNames.favouriteTitle("  Configured name  ", 38197, tile, fallback),
        "configured name takes precedence and is trimmed");
    Test.assertEqualMessage("Hereford St near Montreal St",
        NearbyPageNames.favouriteTitle(" \t\n ", 38197, tile, fallback),
        "whitespace-only name uses raw tile name when cleaning collides");
    Test.assertEqualMessage("Rolleston Ave",
        NearbyPageNames.favouriteTitle("", 52927, tile, fallback),
        "tile match uses cleaned name without a collision");
    Test.assertEqualMessage("Stop 38197",
        NearbyPageNames.favouriteTitle("", 38197, null, fallback),
        "empty name without cached tile uses translatable fallback");
    Test.assertEqualMessage("Stop 99999",
        NearbyPageNames.favouriteTitle(null, 99999, tile, fallback),
        "stop outside cached tile uses fallback");
    Test.assertEqualMessage("Stop 38197",
        NearbyPageNames.favouriteTitle(" \t ", 38197,
            [[38197, -4353000, 17263000, ""]] as Array, fallback),
        "empty tile name also uses fallback");
    Test.assertMessage(!NearbyPageNames.hasConfiguredName(" \t "),
        "blank tile-derived favourite uses wrapped title layout");
    Test.assertMessage(NearbyPageNames.hasConfiguredName(" Hereford St "),
        "configured favourite keeps its own title layout");
    return true;
}
