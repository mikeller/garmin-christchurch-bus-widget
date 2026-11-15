import Toybox.Lang;
import Toybox.Test;
import Toybox.Graphics;

(:debug, :nearby)
class NearbyPageTitleMeasure {
    function width(text as String) as Number {
        return text.length() * 10;
    }
}

(:test, :nearby)
function testNearbyPageTitleWithDistance(logger as Logger) as Boolean {
    var metres = [0, 99, 100, 999, 1000, 1050] as Array<Number>;
    var expected = ["Stop (0 m)", "Stop (99 m)", "Stop (100 m)",
                    "Stop (999 m)", "Stop (1.0 km)", "Stop (1.1 km)"];
    for (var i = 0; i < metres.size(); i++) {
        Test.assertEqualMessage(expected[i],
            NearbyPageTitle.text("Stop", NearbyPageNames.distance(metres[i])),
            "distance in title");
    }
    Test.assertEqualMessage("Favourite", NearbyPageTitle.text("Favourite", null),
        "favourite without nearby distance");
    var fonts = NearbyPageTitle.fonts();
    Test.assertEqualMessage(3, fonts.size(), "system font choices");
    Test.assertEqualMessage(Graphics.FONT_SYSTEM_SMALL, fonts[0], "match favourite title family");
    Test.assertEqualMessage(Graphics.FONT_SYSTEM_TINY, fonts[1], "same system family at smaller size");
    Test.assertEqualMessage(Graphics.FONT_SYSTEM_XTINY, fonts[2], "smallest system family size");

    var measured = new NearbyPageTitleMeasure();
    var width = measured.method(:width);
    var lines = NearbyPageTitle.fit("Hereford St", "234 m", 190, 220, width);
    Test.assertEqualMessage(1, (lines as Array).size(), "short title stays on one line");
    Test.assertEqualMessage("Hereford St (234 m)", (lines as Array)[0], "whole short title");
    lines = NearbyPageTitle.fit("Hereford St", "234 m", 120, 80, width);
    Test.assertEqualMessage("Hereford St", (lines as Array)[0], "do not orphan St");
    Test.assertEqualMessage("(234 m)", (lines as Array)[1], "break before distance");
    lines = NearbyPageTitle.fit("Rolleston Ave near Gloucester St", "188 m",
        200, 220, width);
    Test.assertEqualMessage("Rolleston Ave near", (lines as Array)[0], "first title line");
    Test.assertEqualMessage("Gloucester St (188 m)", (lines as Array)[1],
        "last line keeps distance whole");
    lines = NearbyPageTitle.fit("Alpha Beta Gamma St", "188 m", 180, 180, width);
    Test.assertEqualMessage("Alpha Beta", (lines as Array)[0], "prefer non-orphan break");
    Test.assertEqualMessage("Gamma St (188 m)", (lines as Array)[1], "keep St with its name");
    lines = NearbyPageTitle.fit("LongOneWord", "188 m", 120, 70, width);
    Test.assertEqualMessage("LongOneWord", (lines as Array)[0], "name without spaces");
    Test.assertEqualMessage("(188 m)", (lines as Array)[1],
        "distance fits exactly without an unnecessary leading separator");
    Test.assertMessage(NearbyPageTitle.fit("LongOneWord", "188 m", 120, 69, width) == null,
        "a 69 px line cannot fit the 70 px atomic distance");
    Test.assertMessage(NearbyPageTitle.fit("ExtremelyLongStopNameWithoutSpaces",
        "188 m", 90, 100, width) == null, "font must shrink or name truncate");
    lines = NearbyPageTitle.truncate("ExtremelyLongStopNameWithoutSpaces",
        "188 m", 90, 100, width);
    Test.assertEqualMessage("Extrem...", (lines as Array)[0], "only name truncated");
    Test.assertEqualMessage("(188 m)", (lines as Array)[1], "distance not truncated");
    lines = NearbyPageTitle.fit("Short", null, 80, 100, width);
    Test.assertEqualMessage("Short", (lines as Array)[0], "no distance");
    return true;
}
