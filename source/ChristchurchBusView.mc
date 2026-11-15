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
        
    function initialize(data as Dictionary<String, String or Array>, displayName as String, dataIsStale as Boolean) {
        BaseChristchurchBusView.initialize(displayName, dataIsStale);

        self.data = data;
    }

    function onUpdate(dc as Dc) as Void {
        BaseChristchurchBusView.onUpdate(dc);

        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();

        var lineHeight = dc.getFontHeight(Graphics.FONT_SYSTEM_TINY);

        var nameColumnX = calculateViewPortBoundaryX(cursorY, lineHeight, screenWidth, screenHeight, false);
        var nameColumnXBottom = calculateViewPortBoundaryX(cursorY + (Constants.LINES_TO_SHOW - 1) * (lineHeight + Constants.VERTICAL_SPACE), lineHeight, screenWidth, screenHeight, false);
        if (nameColumnXBottom > nameColumnX) {
            nameColumnX = nameColumnXBottom;
        }

        var now = Time.now();
        var second = now.value();
        var visitsToFit = data["MonitoredStopVisit"] as Array<Dictionary>?;
        // The displayed countdown includes seconds. A new second changes the row
        // text and must refit; a redraw within that second reuses the measured rows.
        if (second != fittedSecond ||
            !DepartureRowsKey.same(visitsToFit, fittedVisits, screenWidth, fittedWidth,
                                   screenHeight, fittedHeight)) {
            fittedRows = [];
            fittedSecond = second;
            fittedWidth = screenWidth;
            fittedHeight = screenHeight;
            fittedVisits = visitsToFit;
            var index = 0;
            var lineCount = 0;
            var rowY = cursorY;
            if (visitsToFit != null) {
                while (lineCount < Constants.LINES_TO_SHOW && index < visitsToFit.size()) {
                    var visitToFit = visitsToFit[index];
                    var departureText = visitToFit["ExpectedDepartureTime"] as String?;
                    var departure = departureText != null ? Utils.parseIsoDate(departureText) : null;
                    if (departure != null) {
                        var difference = departure.compare(now);
                        if (difference >= 0) {
                            var wait = (difference / 60).format("%02d") + ":" + (difference % 60).format("%02d");
                            var rightX = calculateViewPortBoundaryX(rowY, lineHeight, screenWidth, screenHeight, true);
                            var available = rightX - nameColumnX - Constants.HORIZONTAL_SPACE;
                            if (available < 1) {
                                available = 1;
                            }
                            var route = visitToFit["PublishedLineName"] as String?;
                            var destination = visitToFit["DestinationName"] as String?;
                            var fitted = DepartureRowFit.fit(wait, route, destination, available, dc);
                            fittedRows.add([fitted[0], fitted[1], visitToFit["VehicleAtStop"] == true]);
                            rowY += lineHeight + Constants.VERTICAL_SPACE;
                            lineCount++;
                        }
                    }
                    index++;
                }
            }
        }

        var lineCount = 0;
        var visits = data["MonitoredStopVisit"] as Array<Dictionary>?;
        if (visits != null) {
            while (lineCount < fittedRows.size()) {
                var row = fittedRows[lineCount] as Array;
                if (row[2] as Boolean) {
                    dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
                } else {
                    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
                }
                dc.drawText(nameColumnX, cursorY, row[1] as Graphics.FontType,
                            row[0] as String, Graphics.TEXT_JUSTIFY_LEFT);
                cursorY += lineHeight + Constants.VERTICAL_SPACE;
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
            dc.drawText(nameColumnX, cursorY, Graphics.FONT_SYSTEM_TINY, errorMessage, Graphics.TEXT_JUSTIFY_LEFT);
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
