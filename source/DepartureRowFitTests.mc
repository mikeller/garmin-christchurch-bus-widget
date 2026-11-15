import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;

(:debug)
class RowWidthFixture {
    function getTextWidthInPixels(text as String, font as Graphics.FontType) as Number {
        return text.length() * (font == Graphics.FONT_SYSTEM_SMALL ? 6 : 5);
    }
}

(:test)
function testDepartureBoldFontHeights(logger as Logger) as Boolean {
    var fonts = DepartureRowFit.smallerFonts(
        [Graphics.FONT_SYSTEM_SMALL, Graphics.FONT_SYSTEM_TINY, Graphics.FONT_SYSTEM_XTINY],
        [29, 26, 26]);
    Test.assertEqualMessage(2, fonts.size(), "equal-height regular font must be excluded");
    Test.assertEqualMessage(Graphics.FONT_SYSTEM_SMALL, fonts[0], "first font is bold small");
    Test.assertEqualMessage(Graphics.FONT_SYSTEM_TINY, fonts[1], "second font is bold tiny");
    fonts = DepartureRowFit.smallerFonts(
        [Graphics.FONT_SYSTEM_SMALL, Graphics.FONT_SYSTEM_TINY], [26, 26]);
    Test.assertEqualMessage(1, fonts.size(), "no duplicate-height fonts");
    return true;
}

(:test)
function testDeparturePageOneFont(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var fonts = [Graphics.FONT_SYSTEM_SMALL, Graphics.FONT_SYSTEM_TINY];
    var rows = [["16:28", "8", "Lyttelton"], ["30:38", "29", "City Centre"]];
    var widths = [[120, 105], [100, 100]];
    var font = DepartureRowFit.chooseFont(rows, widths, fonts, fixture);
    Test.assertEqualMessage(Graphics.FONT_SYSTEM_TINY, font,
                            "second row cannot keep six destination characters at bold small");
    for (var i = 0; i < rows.size(); i++) {
        var row = rows[i] as Array;
        var text = DepartureRowFit.fit(row[0], row[1], row[2], (widths[1] as Array)[i], font, fixture);
        Test.assertEqualMessage(true, fixture.getTextWidthInPixels(text, font) <= 100,
                                "each row uses one bold font and fits");
    }
    return true;
}

(:test)
function testDeparturePreferLargerBoldFont(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var font = DepartureRowFit.chooseFont([["16:28", "8", "Lyttelton"]],
        [[120], [100]], [Graphics.FONT_SYSTEM_SMALL, Graphics.FONT_SYSTEM_TINY], fixture);
    Test.assertEqualMessage(Graphics.FONT_SYSTEM_SMALL, font,
                            "six destination characters fit in larger bold font");
    return true;
}

(:test)
function testDeparturePreservesWholeRow(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var text = DepartureRowFit.fit("16:28", "8", "Lyttelton", 200,
        Graphics.FONT_SYSTEM_SMALL, fixture);
    Test.assertEqualMessage(true, "16:28: 8 (Lyttelton)".equals(text),
                            "row that fits keeps original text");
    return true;
}

(:test)
function testDepartureTruncatesOnlyDestination(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var text = DepartureRowFit.fit("16:28", "8", "Lyttelton via ferry", 100,
        Graphics.FONT_SYSTEM_TINY, fixture);
    Test.assertEqualMessage(0, text.find("16:28: 8 ("), "time and route unchanged");
    Test.assertEqualMessage(true, text.find("…)") != null, "destination ends in ellipsis");
    Test.assertEqualMessage(true,
        fixture.getTextWidthInPixels(text, Graphics.FONT_SYSTEM_TINY) <= 100,
        "truncated row fits");
    return true;
}

(:test)
function testDepartureMinimumDestination(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var rows = [["16:28", "8", "Lyttelton via ferry"]];
    var fonts = [Graphics.FONT_SYSTEM_SMALL, Graphics.FONT_SYSTEM_TINY];
    // Six characters plus ellipsis need 108 px at small, 90 px at tiny.
    var font = DepartureRowFit.chooseFont(rows, [[107], [90]], fonts, fixture);
    Test.assertEqualMessage(Graphics.FONT_SYSTEM_TINY, font,
                            "choose smaller bold font to retain six characters");
    var text = DepartureRowFit.fit("16:28", "8", "Lyttelton via ferry", 90, font, fixture);
    Test.assertEqualMessage(true, text.find("Lyttel") != null,
                            "at least six destination characters remain");
    return true;
}

(:test)
function testDepartureMissingNames(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var text = DepartureRowFit.fit("16:28", null, null, 100,
        Graphics.FONT_SYSTEM_TINY, fixture);
    Test.assertEqualMessage(true, "16:28:  ()".equals(text), "null names remain empty");
    text = DepartureRowFit.fit("16:28", "", "", 35,
        Graphics.FONT_SYSTEM_TINY, fixture);
    Test.assertEqualMessage(true, "16:28: ".equals(text), "no false ellipsis for empty name");
    return true;
}

(:test)
function testDepartureUnicodeAndNarrowRow(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var text = DepartureRowFit.fit("16:28", "8", "Rāpaki (via ferry)", 90,
        Graphics.FONT_SYSTEM_TINY, fixture);
    Test.assertEqualMessage(true, text.find("…)") != null, "Unicode name truncated");
    text = DepartureRowFit.fit("16:28", "8", "Long destination", 35,
        Graphics.FONT_SYSTEM_TINY, fixture);
    Test.assertEqualMessage(true, "16:28: 8".equals(text), "route retained even in narrow row");
    return true;
}
