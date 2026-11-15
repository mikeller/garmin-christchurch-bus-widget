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

    protected var cursorY as Number = 0;

    function initialize(siteName as String, dataIsStale as Boolean, subtitle as String?, distanceSuffix as String?) {
        View.initialize();

        self.siteName = siteName;
        self.dataIsStale = dataIsStale;
        self.subtitle = subtitle;
        self.distanceSuffix = distanceSuffix;
        titleToDraw = siteName;
    }

    function onLayout(dc as Dc) as Void {
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
