import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;

(:debug)
class RowWidthFixture {
    function getTextWidthInPixels(text as String, font as Graphics.FontType) as Number {
        return text.length() * (font == Graphics.FONT_XTINY ? 3 : 5);
    }
}

(:test)
function testDepartureRowAlreadyFits(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var fit = DepartureRowFit.fit("16:28", "8", "Lyttelton", 200, fixture);
    Test.assertEqualMessage(true, "16:28: 8 (Lyttelton)".equals(fit[0]),
                            "already fits: expected full row, got " + fit[0]);
    Test.assertEqualMessage(Graphics.FONT_SYSTEM_TINY, fit[1],
                            "already fits: expected system tiny, got " + fit[1]);
    return true;
}

(:test)
function testDepartureRowSmallerFont(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var fit = DepartureRowFit.fit("16:28", "8", "Lyttelton", 90, fixture);
    Test.assertEqualMessage(true, "16:28: 8 (Lyttelton)".equals(fit[0]),
                            "smaller font: expected full row, got " + fit[0]);
    Test.assertEqualMessage(Graphics.FONT_XTINY, fit[1],
                            "smaller font: expected xtiny, got " + fit[1]);
    return true;
}

(:test)
function testDepartureRowTruncatesDestination(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var fit = DepartureRowFit.fit("16:28", "8", "Lyttelton via ferry", 70, fixture);
    Test.assertEqualMessage(Graphics.FONT_XTINY, fit[1],
                            "truncate: expected xtiny, got " + fit[1]);
    Test.assertEqualMessage(0, (fit[0] as String).find("16:28: 8 ("),
                            "truncate: expected time and route prefix, got " + fit[0]);
    Test.assertEqualMessage(true, (fit[0] as String).find("…)") != null,
                            "truncate: expected ellipsis and closing bracket, got " + fit[0]);
    Test.assertEqualMessage(true, fixture.getTextWidthInPixels(fit[0], fit[1]) <= 70,
                            "truncate: expected width <= 70, got " + fixture.getTextWidthInPixels(fit[0], fit[1]));
    return true;
}

(:test)
function testDepartureRowEllipsisExactlyFits(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var fit = DepartureRowFit.fit("16:28", "8", "Long destination", 36, fixture);
    Test.assertEqualMessage(true, "16:28: 8 (…)".equals(fit[0]),
                            "exact width: expected parenthesised ellipsis, got " + fit[0]);
    Test.assertEqualMessage(36, fixture.getTextWidthInPixels(fit[0], fit[1]),
                            "exact width: expected 36 pixels, got " + fixture.getTextWidthInPixels(fit[0], fit[1]));
    return true;
}

(:test)
function testDepartureRowKeepsPrefix(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    // The shortest parenthesised form has 12 characters at 3 pixels each;
    // 35 pixels forces the prefix-only fallback without clipping that prefix.
    var fit = DepartureRowFit.fit("16:28", "8", "Long destination", 35, fixture);
    Test.assertEqualMessage(true, "16:28: 8".equals(fit[0]),
                            "prefix fallback: expected time and route only, got " + fit[0]);
    Test.assertEqualMessage(Graphics.FONT_XTINY, fit[1],
                            "prefix fallback: expected xtiny, got " + fit[1]);
    Test.assertEqualMessage(true, fixture.getTextWidthInPixels(fit[0], fit[1]) <= 35,
                            "prefix fallback: expected width <= 35, got " + fixture.getTextWidthInPixels(fit[0], fit[1]));
    return true;
}

(:test)
function testDepartureRowMissingNames(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var fit = DepartureRowFit.fit("16:28", null, null, 100, fixture);
    Test.assertEqualMessage(true, "16:28:  ()".equals(fit[0]),
                            "missing names: expected empty route and destination, got " + fit[0]);
    fit = DepartureRowFit.fit("16:28", "", "", 25, fixture);
    Test.assertEqualMessage(true, "16:28: ".equals(fit[0]),
                            "empty names: expected time prefix without false ellipsis, got " + fit[0]);
    Test.assertEqualMessage(true, fixture.getTextWidthInPixels(fit[0], fit[1]) <= 25,
                            "empty names: expected width <= 25, got " + fixture.getTextWidthInPixels(fit[0], fit[1]));
    return true;
}

(:test)
function testDepartureRowUnicodeDestination(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var fit = DepartureRowFit.fit("16:28", "8", "Rāpaki (via ferry)", 70, fixture);
    Test.assertEqualMessage(0, (fit[0] as String).find("16:28: 8 ("),
                            "Unicode: expected time and route prefix, got " + fit[0]);
    Test.assertEqualMessage(true, (fit[0] as String).find("…)") != null,
                            "Unicode: expected ellipsis, got " + fit[0]);
    Test.assertEqualMessage(true, fixture.getTextWidthInPixels(fit[0], fit[1]) <= 70,
                            "Unicode: expected width <= 70, got " + fixture.getTextWidthInPixels(fit[0], fit[1]));
    return true;
}

(:test)
function testDepartureRowNonPositiveWidth(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var fit = DepartureRowFit.fit("16:28", "8", "Lyttelton", -1, fixture);
    Test.assertEqualMessage(true, "16:28: 8".equals(fit[0]),
                            "negative width: expected time and route fallback, got " + fit[0]);
    return true;
}
