import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;

(:debug)
class RowWidthFixture {
    function width(font as Graphics.FontType, text as String) as Number {
        return text.length() * (font == Graphics.FONT_XTINY ? 3 : 5);
    }
}

(:test)
function testDepartureRowAlreadyFits(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var fit = DepartureRowFit.fit("16:28", "8", "Lyttelton", 200, fixture.method(:width));
    Test.assertEqualMessage(true, "16:28: 8 (Lyttelton)".equals(fit[0]),
                            "already fits: expected full row, got " + fit[0]);
    Test.assertEqualMessage(Graphics.FONT_SYSTEM_TINY, fit[1],
                            "already fits: expected system tiny, got " + fit[1]);
    return true;
}

(:test)
function testDepartureRowSmallerFont(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var fit = DepartureRowFit.fit("16:28", "8", "Lyttelton", 90, fixture.method(:width));
    Test.assertEqualMessage(true, "16:28: 8 (Lyttelton)".equals(fit[0]),
                            "smaller font: expected full row, got " + fit[0]);
    Test.assertEqualMessage(Graphics.FONT_XTINY, fit[1],
                            "smaller font: expected xtiny, got " + fit[1]);
    return true;
}

(:test)
function testDepartureRowTruncatesDestination(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var fit = DepartureRowFit.fit("16:28", "8", "Lyttelton via ferry", 70, fixture.method(:width));
    Test.assertEqualMessage(Graphics.FONT_XTINY, fit[1],
                            "truncate: expected xtiny, got " + fit[1]);
    Test.assertEqualMessage(0, (fit[0] as String).find("16:28: 8 ("),
                            "truncate: expected time and route prefix, got " + fit[0]);
    Test.assertEqualMessage(true, (fit[0] as String).find("…)") != null,
                            "truncate: expected ellipsis and closing bracket, got " + fit[0]);
    Test.assertEqualMessage(true, fixture.width(fit[1], fit[0]) <= 70,
                            "truncate: expected width <= 70, got " + fixture.width(fit[1], fit[0]));
    return true;
}

(:test)
function testDepartureRowEllipsisExactlyFits(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var fit = DepartureRowFit.fit("16:28", "8", "Long destination", 36, fixture.method(:width));
    Test.assertEqualMessage(true, "16:28: 8 (…)".equals(fit[0]),
                            "exact width: expected parenthesised ellipsis, got " + fit[0]);
    Test.assertEqualMessage(36, fixture.width(fit[1], fit[0]),
                            "exact width: expected 36 pixels, got " + fixture.width(fit[1], fit[0]));
    return true;
}

(:test)
function testDepartureRowKeepsPrefix(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    // The shortest parenthesised form has 12 characters at 3 pixels each;
    // 35 pixels forces the prefix-only fallback without clipping that prefix.
    var fit = DepartureRowFit.fit("16:28", "8", "Long destination", 35, fixture.method(:width));
    Test.assertEqualMessage(true, "16:28: 8".equals(fit[0]),
                            "prefix fallback: expected time and route only, got " + fit[0]);
    Test.assertEqualMessage(Graphics.FONT_XTINY, fit[1],
                            "prefix fallback: expected xtiny, got " + fit[1]);
    Test.assertEqualMessage(true, fixture.width(fit[1], fit[0]) <= 35,
                            "prefix fallback: expected width <= 35, got " + fixture.width(fit[1], fit[0]));
    return true;
}
