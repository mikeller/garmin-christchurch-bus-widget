import Toybox.Lang;
import Toybox.Test;

(:test, :nearby)
function testNearbyGlanceTitle(logger as Logger) as Boolean {
    var fallback = "Stop $1$";
    Test.assertEqualMessage("Configured",
        NearbyGlanceTitle.title("  Configured \t", "Nearby", 53090, fallback),
        "configured favourite name takes precedence");
    Test.assertMessage(NearbyGlanceTitle.isBlank(" \t\r\n"), "whitespace-only is blank");
    Test.assertEqualMessage("Nearby",
        NearbyGlanceTitle.title(" \t\n ", " Nearby ", 53090, fallback),
        "blank favourite uses matching cached nearby name");
    Test.assertEqualMessage("Stop 53090",
        NearbyGlanceTitle.title("", null, 53090, fallback),
        "no nearby match uses translatable fallback");
    Test.assertEqualMessage("Stop 53090",
        NearbyGlanceTitle.title(null, " \t", 53090, fallback),
        "blank nearby name uses fallback");
    return true;
}
