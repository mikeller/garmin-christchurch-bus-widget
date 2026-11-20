import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Math;

(:nearby)
class BaseChristchurchBusView extends WatchUi.View {
    protected var siteName as String = "";
    protected var dataIsStale as Boolean = false;
    protected var subtitle as String?;
    protected var distanceSuffix as String?;
    protected var titleToDraw as String = "";
    protected var nearbyPage as Boolean = false;
    protected var favouritePage as Boolean = false;
    protected var staleNearbyPosition as Boolean = false;
    protected var fixSource as NearbyLocation?;
    protected var distanceFixAt as Number = 0;
    protected var distanceFixStale as Boolean = false;
    protected var nearbyTitleLines as Array<String> = [] as Array<String>;
    protected var nearbyFont as Graphics.FontType = Graphics.FONT_SYSTEM_SMALL;
    protected var nearbyLineHeight as Number = 0;
    protected var nearbyStartY as Number = 0;
    protected var fixIndicatorRect as Array<Number>?;
    protected var pairedIndicatorRect as Array<Number>?;
    protected var networkIndicatorRect as Array<Number>?;

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

    function setFavouritePage() as Void {
        favouritePage = true;
    }

    function setStaleNearbyPosition(stale as Boolean) as Void {
        staleNearbyPosition = stale;
    }

    function setFixSource(location as NearbyLocation?) as Void {
        fixSource = location;
    }

    function setDistanceFix(at as Number, stale as Boolean) as Void {
        distanceFixAt = at;
        distanceFixStale = stale;
    }

    protected function refreshFixAge() as Void {
        if (fixSource != null) {
            var old = distanceFixAt != 0 ?
                NearbyFixDecision.staleForData(distanceFixAt, distanceFixStale,
                    false, Time.now().value()) :
                (fixSource as NearbyLocation).isStale();
            staleNearbyPosition = NearbyFixDecision.show(favouritePage,
                distanceSuffix != null, old);
        }
    }

    function onHide() as Void {
        getApp().nearbyViewHidden(self);
    }

    function onShow() as Void {
        getApp().nearbyViewShown(self);
    }

    function onLayout(dc as Dc) as Void {
        // A stale favourite title starts at height / 6; the nearby title
        // starts no higher. Reserve no new title or departure-row space.
        fixIndicatorRect = NearbyFixIndicator.rect(dc.getWidth(), dc.getHeight(),
            dc.getHeight() / 6, true, true, false);
        pairedIndicatorRect = NearbyFixIndicator.rect(dc.getWidth(), dc.getHeight(),
            dc.getHeight() / 6, true, true, true);
        networkIndicatorRect = NearbyFixIndicator.rect(dc.getWidth(), dc.getHeight(),
            dc.getHeight() / 6, true, false, true);
        if (nearbyPage) {
            nearbyStartY = dc.getHeight() / 4;
            var fonts = NearbyPageTitle.effectiveFonts(dc);
            nearbyTitleLines = [];
            // Prefer fewer lines, then a larger font. All width measurements
            // use the chosen font and the chord at the actual baseline.
            for (var i = 0; i < fonts.size(); i++) {
                nearbyFont = fonts[i] as Graphics.FontType;
                var full = NearbyPageTitle.text(siteName, distanceSuffix);
                if (dc.getTextWidthInPixels(full, nearbyFont) <=
                    nearbyLineWidth(dc, nearbyStartY, dc.getFontHeight(nearbyFont))) {
                    nearbyTitleLines = [full];
                    break;
                }
            }
            for (var count = 2; count <= 3 && nearbyTitleLines.size() == 0; count++) {
                nearbyStartY = dc.getHeight() / 6;
                for (var i = 0; i < fonts.size(); i++) {
                    nearbyFont = fonts[i] as Graphics.FontType;
                    var height = dc.getFontHeight(nearbyFont) + Constants.VERTICAL_SPACE;
                    var widths = [] as Array<Number>;
                    for (var n = 0; n < count; n++) {
                        widths.add(nearbyLineWidth(dc, nearbyStartY + n * height,
                            dc.getFontHeight(nearbyFont)));
                    }
                    if (!nearbyRowsFit(dc, nearbyStartY, count, height)) {
                        continue;
                    }
                    var wrapped = NearbyPageTitle.fitDc(siteName, distanceSuffix,
                        widths, dc, nearbyFont);
                    if (wrapped != null && (wrapped as Array).size() == count) {
                        nearbyTitleLines = wrapped as Array<String>;
                        break;
                    }
                }
            }
            if (nearbyTitleLines.size() == 0) {
                nearbyFont = fonts[fonts.size() - 1] as Graphics.FontType;
                var height = dc.getFontHeight(nearbyFont) + Constants.VERTICAL_SPACE;
                var count = nearbyRowsFit(dc, dc.getHeight() / 6, 3, height) ? 3 : 2;
                nearbyStartY = dc.getHeight() / 6;
                var widths = [] as Array<Number>;
                for (var n = 0; n < count; n++) {
                    widths.add(nearbyLineWidth(dc, nearbyStartY + n * height,
                        dc.getFontHeight(nearbyFont)));
                }
                var truncated = NearbyPageTitle.truncateDc(siteName, distanceSuffix,
                    widths, dc, nearbyFont);
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

    private function nearbyRowsFit(dc as Dc, start as Number, lines as Number,
                                   titleLineHeight as Number) as Boolean {
        var rowsStart = start + lines * titleLineHeight +
            Constants.LINE_WIDTH + Constants.VERTICAL_SPACE;
        var rowHeight = dc.getFontHeight(Graphics.FONT_XTINY) + Constants.VERTICAL_SPACE;
        var bottom = rowsStart + 2 * rowHeight;
        return NearbyPageTitle.rowsFit(start, lines, titleLineHeight,
            Constants.LINE_WIDTH + Constants.VERTICAL_SPACE, rowHeight,
            dc.getHeight(), nearbyWidthAt(dc, bottom));
    }

    protected function departureRowsToShow(dc as Dc, rowHeight as Number) as Number {
        var count = Constants.LINES_TO_SHOW;
        if (nearbyPage) {
            while (count > 2 &&
                   cursorY + count * (rowHeight + Constants.VERTICAL_SPACE) >
                       dc.getHeight() - 5) {
                count--;
            }
        }
        return count;
    }

    private function nearbyLineWidth(dc as Dc, y as Number, fontHeight as Number) as Number {
        var top = nearbyWidthAt(dc, y);
        var bottom = nearbyWidthAt(dc, y + fontHeight);
        return top < bottom ? top : bottom;
    }

    function onUpdate(dc as Dc) as Void {
        refreshFixAge();
        dc.setColor(Constants.COLOUR_FOREGROUND, Constants.COLOUR_BACKGROUND);
        dc.clear();

        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();

        if (dataIsStale) {
            var connectionProblemIcon = WatchUi.loadResource(Rez.Drawables.ConnectionProblemIcon) as BitmapReference;
            var networkBounds = staleNearbyPosition ?
                pairedIndicatorRect : networkIndicatorRect;
            if (networkBounds != null) {
                dc.drawBitmap((networkBounds as Array<Number>)[3],
                    (networkBounds as Array<Number>)[4], connectionProblemIcon);
            }
        }
        drawNearbyFixIndicator(dc);

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

        cursorY = staleNearbyPosition ? screenHeight / 6 : screenHeight / 10;
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

    (:nearby)
    protected function drawNearbyFixIndicator(dc as Dc) as Void {
        if (staleNearbyPosition) {
            var bounds = dataIsStale ? pairedIndicatorRect : fixIndicatorRect;
            if (bounds != null) {
                NearbyFixIndicator.draw(dc, bounds as Array<Number>);
            }
        }
    }

    (:noNearby)
    protected function drawNearbyFixIndicator(dc as Dc) as Void {}

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

// Excluded devices retain master's plain favourite title and underline.
(:noNearby)
class BaseChristchurchBusView extends WatchUi.View {
    protected var siteName as String = "";
    protected var dataIsStale as Boolean = false;
    protected var cursorY as Number = 0;

    function initialize(siteName as String, dataIsStale as Boolean,
                        subtitle as String?, distanceSuffix as String?) {
        View.initialize();
        self.siteName = siteName;
        self.dataIsStale = dataIsStale;
    }

    function setNearbyPage() as Void {}
    function setStaleNearbyPosition(stale as Boolean) as Void {}

    protected function departureRowsToShow(dc as Dc, rowHeight as Number) as Number {
        return Constants.LINES_TO_SHOW;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Constants.COLOUR_FOREGROUND, Constants.COLOUR_BACKGROUND);
        dc.clear();
        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();
        if (dataIsStale) {
            var icon = WatchUi.loadResource(Rez.Drawables.ConnectionProblemIcon) as BitmapReference;
            dc.drawBitmap(screenWidth / 2 - 10, 2 * Constants.VERTICAL_SPACE, icon);
        }
        var titleWidth = getTitleWidth(dc);
        cursorY = screenHeight / 10;
        dc.drawText(titleWidth / 2, cursorY, Graphics.FONT_SYSTEM_SMALL, siteName,
            Graphics.TEXT_JUSTIFY_CENTER);
        cursorY += dc.getFontHeight(Graphics.FONT_SYSTEM_SMALL) + Constants.VERTICAL_SPACE;
        dc.setPenWidth(Constants.LINE_WIDTH);
        dc.drawLine(0, cursorY, titleWidth, cursorY);
        cursorY += Constants.LINE_WIDTH + Constants.VERTICAL_SPACE;
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
