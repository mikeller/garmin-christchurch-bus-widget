import Toybox.Lang;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Time.Gregorian;

class ChristchurchBusView extends BaseChristchurchBusView {
    var data as Dictionary<String, String or Array> = {} as Dictionary<String, String or Array>;
    // One bounded entry shared across view instances (a cache hit recreates the view).
    private static var fittedRows as Array = [];
    private static var fittedSecond as Number = -1;
    private static var fittedWidth as Number = -1;
    private static var fittedHeight as Number = -1;
    private static var fittedVisits as Array?;
    private static var fittedFont as Graphics.FontType = Graphics.FONT_SYSTEM_TINY;
    private static var fittedFontKey as Graphics.FontType = Graphics.FONT_SYSTEM_TINY;
    private static var fittedLineHeight as Number = 0;
    private static var fittedX as Number = 0;
        
    function initialize(data as Dictionary<String, String or Array>, displayName as String, dataIsStale as Boolean) {
        BaseChristchurchBusView.initialize(displayName, dataIsStale);

        self.data = data;
    }

    function onUpdate(dc as Dc) as Void {
        BaseChristchurchBusView.onUpdate(dc);

        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();

        var now = Time.now();
        var second = now.value();
        var visitsToFit = data["MonitoredStopVisit"] as Array<Dictionary>?;
        // The displayed countdown includes seconds. A new second changes the row
        // text and must refit; a redraw within that second reuses the measured rows.
        if (second != fittedSecond ||
            !DepartureRowsKey.same(visitsToFit, fittedVisits, screenWidth, fittedWidth,
                                   screenHeight, fittedHeight, fittedFont, fittedFontKey)) {
            fittedRows = [];
            fittedSecond = second;
            fittedWidth = screenWidth;
            fittedHeight = screenHeight;
            fittedVisits = visitsToFit;
            var index = 0;
            var rows = [] as Array;
            if (visitsToFit != null) {
                while (rows.size() < Constants.LINES_TO_SHOW && index < visitsToFit.size()) {
                    var visitToFit = visitsToFit[index];
                    var departureText = visitToFit["ExpectedDepartureTime"] as String?;
                    var departure = departureText != null ? Utils.parseIsoDate(departureText) : null;
                    if (departure != null) {
                        var difference = departure.compare(now);
                        if (difference >= 0) {
                            var wait = (difference / 60).format("%02d") + ":" + (difference % 60).format("%02d");
                            rows.add([wait, visitToFit["PublishedLineName"],
                                      visitToFit["DestinationName"], visitToFit["VehicleAtStop"] == true]);
                        }
                    }
                    index++;
                }
            }
            var fonts = DepartureRowFit.effectiveFonts(dc);
            var widths = [] as Array;
            var lefts = [] as Array<Number>;
            for (var f = 0; f < fonts.size(); f++) {
                var height = dc.getFontHeight(fonts[f]);
                var step = height + Constants.VERTICAL_SPACE;
                var left = calculateViewPortBoundaryX(cursorY, height, screenWidth, screenHeight, false);
                var bottomLeft = calculateViewPortBoundaryX(
                    cursorY + (Constants.LINES_TO_SHOW - 1) * step, height,
                    screenWidth, screenHeight, false);
                if (bottomLeft > left) {
                    left = bottomLeft;
                }
                lefts.add(left);
                var limits = [] as Array<Number>;
                for (var i = 0; i < rows.size(); i++) {
                    var rowY = cursorY + i * step;
                    var right = calculateViewPortBoundaryX(rowY, height, screenWidth, screenHeight, true);
                    limits.add(rowY + height <= screenHeight - Constants.VERTICAL_SPACE ?
                        right - left - Constants.HORIZONTAL_SPACE : 0);
                }
                widths.add(limits);
            }
            fittedFont = DepartureRowFit.chooseFont(rows, widths, fonts, dc);
            fittedFontKey = fittedFont;
            fittedLineHeight = dc.getFontHeight(fittedFont);
            for (var f = 0; f < fonts.size(); f++) {
                if (fonts[f] == fittedFont) {
                    fittedX = lefts[f];
                    var limits = widths[f] as Array<Number>;
                    for (var i = 0; i < rows.size(); i++) {
                        var row = rows[i] as Array;
                        var fitted = DepartureRowFit.fit(row[0] as String, row[1] as String?,
                            row[2] as String?, limits[i], fittedFont, dc);
                        fittedRows.add([fitted, row[3]]);
                    }
                    break;
                }
            }
        }

        var lineCount = 0;
        var visits = data["MonitoredStopVisit"] as Array<Dictionary>?;
        if (visits != null) {
            while (lineCount < fittedRows.size()) {
                var row = fittedRows[lineCount] as Array;
                if (row[1] as Boolean) {
                    dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
                } else {
                    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
                }
                dc.drawText(fittedX, cursorY, fittedFont,
                            row[0] as String, Graphics.TEXT_JUSTIFY_LEFT);
                cursorY += fittedLineHeight + Constants.VERTICAL_SPACE;
                lineCount++;
            }
        } else {
            var errorMessage = "";
            var errorCondition = data["ErrorCondition"] as Dictionary<String, String or Dictionary>?;
            if (errorCondition != null) {
                errorMessage = Constants.UNKNOWN_ERROR_STRING;
                var errorKeys = errorCondition.keys();
                var error = null;
                for (var i = 0; i < errorKeys.size(); i++) {
                    if (!"Description".equals(errorKeys[i])) {
                        error = errorKeys[i];

                        break;
                    }
                }
                if (error != null) {
                    var errorText = (errorCondition[error] as Dictionary<String, String>)["ErrorText"];
                    if ("OtherError".equals(error) && "No trips on stop.".equals(errorText)) {
                        errorMessage = Constants.NO_BUSES_STRING;
                    } else {
                        errorMessage = error + ": " + errorText;
                    }
                } else {
                    var errorDescription = errorCondition["Description"] as String?;
                    if (errorDescription != null) {
                        errorMessage = errorDescription;
                    }
                }
            } else {
                errorMessage = Constants.NO_BUSES_STRING;
            }

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawText(calculateViewPortBoundaryX(cursorY,
                dc.getFontHeight(Graphics.FONT_SYSTEM_TINY), screenWidth, screenHeight, false),
                cursorY, Graphics.FONT_SYSTEM_TINY, errorMessage, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

   (:roundScreen)
    private function calculateViewPortBoundaryX(y as Number, fontHeight as Number, screenWidth as Number, screenHeight as Number, rightSide as Boolean) as Number {
        var circleOriginX = screenWidth / 2;
        var circleOriginY = screenHeight / 2;

        if (y > circleOriginY) {
            y += fontHeight;
        }
        // Keep the chord calculation defined if the last row falls beyond the circle.
        if (y < 0) { y = 0; }
        if (y > screenHeight) { y = screenHeight; }
        var normalisedY = 1.0f * (circleOriginY - y) / circleOriginY;
        var angle = Math.asin(normalisedY);
        if (rightSide) {
            angle += Math.PI;
        }
        var normalisedX = Math.cos(angle);
        return Math.round(circleOriginX - (normalisedX * circleOriginX)).toNumber();
    }

    (:semioctagonalScreen)
    private function calculateViewPortBoundaryX(y as Number, fontHeight as Number, screenWidth as Number, screenHeight as Number, rightSide as Boolean) as Number {        
        if (y > screenHeight / 2) {
            y += fontHeight;
        }

        var x;
        if (y < Constants.SEMIOCTAGONAL_CORNER_HEIGHT) {
            x = Constants.SEMIOCTAGONAL_CORNER_HEIGHT - y;
        } else if (y < screenHeight - Constants.SEMIOCTAGONAL_CORNER_HEIGHT) {
            x = 0;
        } else {
            x = y - (screenHeight - Constants.SEMIOCTAGONAL_CORNER_HEIGHT);
        }

        if (rightSide) {
            x = screenWidth - x;
        }

        return x;
    }
}
