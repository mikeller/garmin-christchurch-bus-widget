import Toybox.Lang;
import Toybox.Graphics;

// Empty-favourites location and tile states use a centred message instead of
// the bus-page header, whose near-top title and hint clip on round screens.
(:nearby)
class NearbyStatusView extends BaseChristchurchBusView {
    private var lines as Array<String> = [] as Array<String>;
    private var font as Graphics.FontType = Graphics.FONT_XTINY;
    private var lineHeight as Number = 0;
    private var startY as Number = 0;
    private var layoutWidth as Number = -1;
    private var layoutHeight as Number = -1;
    private var layoutDc as Dc?;

    function initialize(title as String, hint as String?) {
        BaseChristchurchBusView.initialize(title, false, hint, null);
    }

    private function measure(text as String) as Number {
        return (layoutDc as Dc).getTextWidthInPixels(text, font);
    }

    (:roundScreen)
    private function safeWidth(dc as Dc) as Number {
        return dc.getWidth() * 70 / 100;
    }

    (:semioctagonalScreen)
    private function safeWidth(dc as Dc) as Number {
        return 96; // BaseChristchurchBusView uses a 112 px title region.
    }

    function onLayout(dc as Dc) as Void {
        if (dc.getWidth() == layoutWidth && dc.getHeight() == layoutHeight) {
            return;
        }
        layoutWidth = dc.getWidth();
        layoutHeight = dc.getHeight();
        lines = [];
        // The central three-line band has a wider chord than the top of a
        // round display. Keep a margin even at the outer lines of that band.
        var maxWidth = safeWidth(dc);
        var candidates = [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL,
                          Graphics.FONT_TINY, Graphics.FONT_XTINY];
        layoutDc = dc;
        for (var i = 0; i < candidates.size(); i++) {
            font = candidates[i] as Graphics.FontType;
            var titleLines = NearbyStatusLayout.wrap(siteName, maxWidth, method(:measure), 2);
            var hintLines = subtitle == null ? [] as Array<String> :
                NearbyStatusLayout.wrap(subtitle as String, maxWidth, method(:measure), 2);
            if (titleLines == null || hintLines == null ||
                (titleLines as Array).size() + (hintLines as Array).size() > 3) {
                continue;
            }
            lineHeight = dc.getFontHeight(font) + Constants.VERTICAL_SPACE;
            if (((titleLines as Array).size() + (hintLines as Array).size()) * lineHeight >
                dc.getHeight() * 2 / 5) {
                continue;
            }
            lines = titleLines as Array<String>;
            for (var j = 0; j < (hintLines as Array).size(); j++) {
                lines.add((hintLines as Array<String>)[j]);
            }
            break;
        }
        layoutDc = null;
        if (lines.size() == 0) {
            // An unexpectedly long translation must never leave a blank page.
            font = Graphics.FONT_XTINY;
            lineHeight = dc.getFontHeight(font) + Constants.VERTICAL_SPACE;
            lines = ["..."];
        }
        startY = (dc.getHeight() - lines.size() * lineHeight) / 2;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Constants.COLOUR_FOREGROUND, Constants.COLOUR_BACKGROUND);
        dc.clear();
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(dc.getWidth() / 2, startY + i * lineHeight, font,
                lines[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}
