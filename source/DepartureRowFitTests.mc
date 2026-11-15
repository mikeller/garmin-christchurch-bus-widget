import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;

(:debug)
class RowWidthFixture {
    function getTextWidthInPixels(text as String, font as Graphics.FontType) as Number {
        Test.assertEqualMessage(Graphics.FONT_XTINY, font, "every row uses the fixed XTINY font");
        return text.length() * 3;
    }
}

(:test)
function testDepartureRowsKeepOneFont(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var rows = [["16:28", "8", "Lyttelton", 200],
                ["30:38", "29", "City Centre via Hereford", 66]];
    for (var i = 0; i < rows.size(); i++) {
        var row = rows[i] as Array;
        var text = DepartureRowFit.fit(row[0], row[1], row[2], row[3], fixture);
        Test.assertEqualMessage(true, fixture.getTextWidthInPixels(text, Graphics.FONT_XTINY) <= row[3],
                                "row fits using the one regular Mk1 font");
    }
    return true;
}

(:test)
function testDepartureRowAlreadyFits(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var text = DepartureRowFit.fit("16:28", "8", "Lyttelton", 200, fixture);
    Test.assertEqualMessage(true, "16:28: 8 (Lyttelton)".equals(text),
                            "already fitting row unchanged");
    return true;
}

(:test)
function testDepartureRowTruncatesDestination(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var text = DepartureRowFit.fit("16:28", "8", "Lyttelton via ferry", 70, fixture);
    Test.assertEqualMessage(0, text.find("16:28: 8 ("), "time and route unchanged");
    Test.assertEqualMessage(true, text.find("…)") != null, "destination ellipsis included");
    Test.assertEqualMessage(true, fixture.getTextWidthInPixels(text, Graphics.FONT_XTINY) <= 70,
                            "truncated row fits");
    return true;
}

(:test)
function testDepartureRowEllipsisExactlyFits(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var text = DepartureRowFit.fit("16:28", "8", "Long destination", 36, fixture);
    Test.assertEqualMessage(true, "16:28: 8 (…)".equals(text), "36 px ellipsis fits exactly");
    return true;
}

(:test)
function testDepartureRowLongPrefix(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var text = DepartureRowFit.fit("123:45", "LongRoute99", "City", 60, fixture);
    Test.assertEqualMessage(true, "123:45: LongRoute99".equals(text),
                            "long time and route never truncated");
    return true;
}

(:test)
function testDepartureRowMissingNames(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var text = DepartureRowFit.fit("16:28", null, null, 100, fixture);
    Test.assertEqualMessage(true, "16:28:  ()".equals(text), "null names remain empty");
    text = DepartureRowFit.fit("16:28", "", "", 25, fixture);
    Test.assertEqualMessage(true, "16:28: ".equals(text), "no false ellipsis for empty name");
    return true;
}

(:test)
function testDepartureRowUnicodeAndNarrowRow(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var text = DepartureRowFit.fit("16:28", "8", "Rāpaki (via ferry)", 70, fixture);
    Test.assertEqualMessage(true, text.find("…)") != null, "Unicode name truncated");
    text = DepartureRowFit.fit("16:28", "8", "Long destination", -1, fixture);
    Test.assertEqualMessage(true, "16:28: 8".equals(text), "route retained in zero-width row");
    return true;
}
