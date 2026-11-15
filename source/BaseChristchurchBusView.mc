import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Time.Gregorian;

class BaseChristchurchBusView extends WatchUi.View {
    protected var siteName as String = "";
    protected var dataIsStale as Boolean = false;
    protected var subtitle as String?;
    protected var distanceSuffix as String?;
    protected var titleToDraw as String = "";
    protected var nearbyPage as Boolean = false;
    protected var nearbyTitleLines as Array<String> = [] as Array<String>;
    protected var nearbyFont as Graphics.FontType = Graphics.FONT_XTINY;
    protected var nearbyLineHeight as Number = 0;

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
            // Centre the title lower than the normal header, where a round
            // screen has a substantially wider chord.
            var width = dc.getWidth() * 70 / 100;
            var fonts = [Graphics.FONT_SYSTEM_SMALL, Graphics.FONT_SMALL,
                         Graphics.FONT_TINY, Graphics.FONT_XTINY];
            nearbyTitleLines = [];
            for (var i = 0; i < fonts.size(); i++) {
                nearbyFont = fonts[i] as Graphics.FontType;
                var wrapped = NearbyStatusLayout.wrapDc(siteName, width, dc, nearbyFont, 2);
                if (wrapped != null &&
                    (wrapped as Array).size() * dc.getFontHeight(nearbyFont) <= dc.getHeight() / 4) {
                    nearbyTitleLines = wrapped as Array<String>;
                    break;
                }
            }
            if (nearbyTitleLines.size() == 0) {
                nearbyFont = Graphics.FONT_XTINY;
                var shortened = siteName;
                while (shortened.length() > 0 &&
                    dc.getTextWidthInPixels(shortened + "...", nearbyFont) > width) {
                    shortened = shortened.substring(0, shortened.length() - 1);
                }
                nearbyTitleLines = [shortened + "..."];
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
            cursorY = screenHeight / 5;
            for (var i = 0; i < nearbyTitleLines.size(); i++) {
                dc.drawText(screenWidth / 2, cursorY, nearbyFont, nearbyTitleLines[i],
                    Graphics.TEXT_JUSTIFY_CENTER);
                cursorY += nearbyLineHeight;
            }
            dc.setPenWidth(Constants.LINE_WIDTH);
            dc.drawLine(screenWidth * 15 / 100, cursorY,
                screenWidth * 85 / 100, cursorY);
            cursorY += Constants.LINE_WIDTH + Constants.VERTICAL_SPACE;
            if (subtitle != null) {
                dc.drawText(screenWidth / 2, cursorY, Graphics.FONT_SYSTEM_TINY,
                    subtitle as String, Graphics.TEXT_JUSTIFY_CENTER);
                cursorY += dc.getFontHeight(Graphics.FONT_SYSTEM_TINY) + Constants.VERTICAL_SPACE;
            }
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

    (:semioctagonalScreen)
    private function getTitleWidth(dc as Dc) as Number {
        return 112;
    }
}
