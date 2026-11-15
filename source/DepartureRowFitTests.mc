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
function testDepartureRowFit(logger as Logger) as Boolean {
    var fixture = new RowWidthFixture();
    var fit = DepartureRowFit.fit("16:28", "8", "Lyttelton", 200, fixture.method(:width));
    Test.assertEqual("16:28: 8 (Lyttelton)", fit[0]);
    Test.assertEqual(Graphics.FONT_SYSTEM_TINY, fit[1]);

    fit = DepartureRowFit.fit("16:28", "8", "Lyttelton", 90, fixture.method(:width));
    Test.assertEqual("16:28: 8 (Lyttelton)", fit[0]);
    Test.assertEqual(Graphics.FONT_XTINY, fit[1]);

    fit = DepartureRowFit.fit("16:28", "8", "Lyttelton via ferry", 70, fixture.method(:width));
    Test.assertEqual(Graphics.FONT_XTINY, fit[1]);
    Test.assertEqual(0, (fit[0] as String).find("16:28: 8 ("));
    Test.assertEqual(true, (fit[0] as String).find("…)") != null);
    Test.assertEqual(true, fixture.width(fit[1], fit[0]) <= 70);

    fit = DepartureRowFit.fit("16:28", "8", "Long destination", 38, fixture.method(:width));
    Test.assertEqual("16:28: 8", fit[0]);
    return true;
}
