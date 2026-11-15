import Toybox.Lang;
import Toybox.Test;
import Toybox.Graphics;

(:debug, :nearby)
class NearbyPageTitleTestMeasure {
    function width(text as String) as Number {
        return text.length() * 10;
    }
}

(:test, :nearby)
function testNearbyPageTitleWithDistance(logger as Logger) as Boolean {
    var fonts = NearbyPageTitle.fonts();
    Test.assertEqualMessage(3, fonts.size(), "ordered system fonts");
    Test.assertEqualMessage(Graphics.FONT_SYSTEM_SMALL, fonts[0], "first choice");
    Test.assertEqualMessage(Graphics.FONT_SYSTEM_TINY, fonts[1], "second choice");
    Test.assertEqualMessage(Graphics.FONT_SYSTEM_XTINY, fonts[2], "last choice");
    var measured = new NearbyPageTitleTestMeasure();
    var selectedFont = -1;
    var limits = [120, 180, 400] as Array<Number>;
    for (var f = 0; f < fonts.size(); f++) {
        if (NearbyPageTitle.fitLines("Hereford St", "248 m", [limits[f]], measured) != null) {
            selectedFont = f;
            break;
        }
    }
    Test.assertEqualMessage(2, selectedFont, "one line tries fonts in descending size");
    var name = "Hereford St near Montreal St";
    var full = NearbyPageTitle.fitLines(name, "248 m", [400], measured);
    Test.assertEqualMessage("Hereford St near Montreal St (248 m)",
        (full as Array)[0], "one line preserves near");
    var two = NearbyPageTitle.fitLines(name, "248 m", [160, 220], measured);
    Test.assertEqualMessage("Hereford St /", (two as Array)[0],
        "slash joins the preceding street");
    Test.assertEqualMessage("Montreal St (248 m)", (two as Array)[1],
        "second street and whole distance");
    var three = NearbyPageTitle.fitLines(name, "248 m", [160, 130, 80], measured);
    Test.assertEqualMessage("Hereford St /", (three as Array)[0], "three line slash");
    Test.assertEqualMessage("Montreal St", (three as Array)[1], "no orphan St");
    Test.assertMessage(!"St".equals((three as Array)[1]), "road suffix not alone");
    Test.assertEqualMessage("(248 m)", (three as Array)[2], "whole distance");
    var other = NearbyPageTitle.fitLines("Hereford St near Cambridge Tce",
        "234 m", [160, 130, 80], measured);
    Test.assertEqualMessage("Cambridge Tce", (other as Array)[1],
        "different cross street remains distinguishable");
    Test.assertMessage(!((other as Array)[1] as String).equals((three as Array)[1]),
        "cross streets differ");
    Test.assertMessage(NearbyPageTitle.fitLines(name, "248 m", [160, 130, 69],
        measured) == null, "distance cannot be split");
    var longName = "ExtremelyLongStopNameWithoutSpaces";
    Test.assertMessage(NearbyPageTitle.fitLines(longName, "188 m",
        [90, 100, 100], measured) == null, "truncation is last resort");
    var shortened = NearbyPageTitle.truncate(longName, "188 m",
        [90, 100, 100], measured);
    Test.assertEqualMessage("(188 m)", (shortened as Array)[(shortened as Array).size() - 1],
        "distance not truncated");
    Test.assertMessage(((shortened as Array)[0] as String).find("...") != null,
        "truncated name marked");
    Test.assertEqualMessage("Stop (99 m)", NearbyPageTitle.text("Stop", "99 m"),
        "distance suffix");
    Test.assertMessage(NearbyPageTitle.rowsFit(40, 3, 28, 5, 28, 240, 170),
        "three title lines plus two departures fit 240 px round profile");
    Test.assertMessage(!NearbyPageTitle.rowsFit(40, 3, 28, 5, 28, 170, 170),
        "short profile must fall back to two lines");
    Test.assertMessage(!NearbyPageTitle.rowsFit(40, 3, 28, 5, 28, 240, 60),
        "bottom departure must have usable chord width");
    return true;
}
