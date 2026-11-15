import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Math;

class BaseChristchurchBusView extends WatchUi.View {
    protected var siteName as String = "";
    protected var dataIsStale as Boolean = false;
    protected var subtitle as String?;
    protected var distanceSuffix as String?;
    protected var titleToDraw as String = "";
    protected var nearbyPage as Boolean = false;
    protected var nearbyTitleLines as Array<String> = [] as Array<String>;
    protected var nearbyFont as Graphics.FontType = Graphics.FONT_SYSTEM_SMALL;
    protected var nearbyLineHeight as Number = 0;
    protected var nearbyStartY as Number = 0;

    protected var cursorY as Number = 0;

    function initialize(siteName as String, dataIsStale as Boolean, subtitle as String?, distanceSuffix as String?) {
        View.initialize();

        self.siteName = siteName;
        self.dataIsStale = dataIsStale;
        self.subtitle = subtitle;
        self.distanceSuffix = distanceSuffix;
        titleToDraw = siteName;
    }

    function setNearbyPage() as Void {
        nearbyPage = true;
    }

    function onLayout(dc as Dc) as Void {
        if (nearbyPage) {
            // One-line titles sit nearer the broad middle of a round screen.
            // Two-line titles start higher to preserve room for departures.
            nearbyStartY = dc.getHeight() / 4;
            var fonts = NearbyPageTitle.fonts();
            nearbyTitleLines = [];
            // Prefer a single line, even at a smaller system-font size, over
            // a visually awkward break in a short name such as "Hereford St".
            for (var i = 0; i < fonts.size(); i++) {
                nearbyFont = fonts[i] as Graphics.FontType;
                var full = NearbyPageTitle.text(siteName, distanceSuffix);
                if (dc.getTextWidthInPixels(full, nearbyFont) <=
                    nearbyWidthAt(dc, nearbyStartY)) {
                    nearbyTitleLines = [full];
                    break;
                }
            }
            if (nearbyTitleLines.size() == 0) {
                nearbyStartY = dc.getHeight() / 6;
            }
            for (var i = 0; nearbyTitleLines.size() == 0 && i < fonts.size(); i++) {
                nearbyFont = fonts[i] as Graphics.FontType;
                var height = dc.getFontHeight(nearbyFont) + Constants.VERTICAL_SPACE;
                var firstWidth = nearbyWidthAt(dc, nearbyStartY);
                var secondWidth = nearbyWidthAt(dc, nearbyStartY + height);
                var wrapped = NearbyPageTitle.fitDc(siteName, distanceSuffix,
                    firstWidth, secondWidth, dc, nearbyFont);
                if (wrapped != null &&
                    (wrapped as Array).size() * dc.getFontHeight(nearbyFont) <= dc.getHeight() / 4) {
                    nearbyTitleLines = wrapped as Array<String>;
                    break;
                }
            }
            if (nearbyTitleLines.size() == 0) {
                nearbyFont = Graphics.FONT_SYSTEM_SMALL;
                var firstWidth = nearbyWidthAt(dc, nearbyStartY);
                var secondWidth = nearbyWidthAt(dc, nearbyStartY +
                    dc.getFontHeight(nearbyFont) + Constants.VERTICAL_SPACE);
                var truncated = NearbyPageTitle.truncateDc(siteName, distanceSuffix,
                    firstWidth, secondWidth, dc, nearbyFont);
                nearbyTitleLines = truncated == null ? [NearbyPageTitle.text("", distanceSuffix)] :
                    truncated as Array<String>;
            }
            nearbyLineHeight = dc.getFontHeight(nearbyFont) + Constants.VERTICAL_SPACE;
            return;
        }
        if (distanceSuffix != null) {
            var name = siteName;
            var suffix = distanceSuffix as String;
            var maxWidth = getTitleWidth(dc) - 8;
            while (name.length() > 0 &&
                dc.getTextWidthInPixels(name + suffix, Graphics.FONT_SYSTEM_SMALL) > maxWidth) {
                name = name.substring(0, name.length() - 1);
            }
            titleToDraw = name + suffix;
        }
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Constants.COLOUR_FOREGROUND, Constants.COLOUR_BACKGROUND);
        dc.clear();

        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();

        if (dataIsStale) {
            var connectionProblemIcon = WatchUi.loadResource(Rez.Drawables.ConnectionProblemIcon) as BitmapReference;
            dc.drawBitmap(screenWidth / 2 - 10, 2 * Constants.VERTICAL_SPACE, connectionProblemIcon);
        }

        if (nearbyPage) {
            cursorY = nearbyStartY;
            for (var i = 0; i < nearbyTitleLines.size(); i++) {
                dc.drawText(screenWidth / 2, cursorY, nearbyFont, nearbyTitleLines[i],
                    Graphics.TEXT_JUSTIFY_CENTER);
                cursorY += nearbyLineHeight;
            }
            dc.setPenWidth(Constants.LINE_WIDTH);
            dc.drawLine(screenWidth * 15 / 100, cursorY,
                screenWidth * 85 / 100, cursorY);
            cursorY += Constants.LINE_WIDTH + Constants.VERTICAL_SPACE;
            return;
        }
        var titleWidth = getTitleWidth(dc);

        cursorY = screenHeight / 10;
        dc.drawText(titleWidth / 2, cursorY, Graphics.FONT_SYSTEM_SMALL, titleToDraw, Graphics.TEXT_JUSTIFY_CENTER);
        cursorY += dc.getFontHeight(Graphics.FONT_SYSTEM_SMALL) + Constants.VERTICAL_SPACE;
        dc.setPenWidth(Constants.LINE_WIDTH);
        dc.drawLine(0, cursorY, titleWidth, cursorY);
        cursorY += Constants.LINE_WIDTH + Constants.VERTICAL_SPACE;
        if (subtitle != null) {
            dc.drawText(titleWidth / 2, cursorY, Graphics.FONT_SYSTEM_TINY, subtitle as String, Graphics.TEXT_JUSTIFY_CENTER);
            cursorY += dc.getFontHeight(Graphics.FONT_SYSTEM_TINY) + Constants.VERTICAL_SPACE;
        }
    }

    (:roundScreen)
    private function getTitleWidth(dc as Dc) as Number {
        return dc.getWidth();
    }

    (:roundScreen)
    private function nearbyWidthAt(dc as Dc, y as Number) as Number {
        var radius = dc.getWidth() / 2 - 5;
        var offset = y - dc.getHeight() / 2;
        var squared = radius * radius - offset * offset;
        return squared > 0 ? (Math.sqrt(squared.toDouble()) * 2).toNumber() - 8 :
            dc.getWidth() / 2;
    }

    (:semioctagonalScreen)
    private function nearbyWidthAt(dc as Dc, y as Number) as Number {
        return 96; // Inside the 112 px main title window with a margin.
    }

    (:semioctagonalScreen)
    private function getTitleWidth(dc as Dc) as Number {
        return 112;
    }
}
