import Toybox.Lang;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Time.Gregorian;

class ChristchurchBusView extends BaseChristchurchBusView {
    //private var dateFont as Graphics.FontDefinition = Graphics.FONT_SYSTEM_TINY;

    var data as Dictionary<String, String or Array> = {} as Dictionary<String, String or Array>;
    //private var displayName as String = "";
        
    function initialize(data as Dictionary<String, String or Array>, displayName as String, dataIsStale as Boolean) {
        BaseChristchurchBusView.initialize(displayName, dataIsStale);

        self.data = data;
        //self.displayName = displayName;
    }

    function onUpdate(dc as Dc) as Void {
        BaseChristchurchBusView.onUpdate(dc);

        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();

        var lineHeight = dc.getFontHeight(Graphics.FONT_SYSTEM_TINY);
        // if (dc.getFontHeight(Graphics.FONT_SYSTEM_XTINY) == lineHeight) {
        //     dateFont = Graphics.FONT_SYSTEM_XTINY;
        // }

        var nameColumnX = calculateViewPortBoundaryX(cursorY, lineHeight, screenWidth, screenHeight, false);
        var nameColumnXBottom = calculateViewPortBoundaryX(cursorY + (Constants.LINES_TO_SHOW - 1) * (lineHeight + Constants.VERTICAL_SPACE), lineHeight, screenWidth, screenHeight, false);
        if (nameColumnXBottom > nameColumnX) {
            nameColumnX = nameColumnXBottom;
        }

        var columnsX = [
            nameColumnX,
        ] as Array<Number>;

        var index = 0;
        var lineCount = 0;
        var visits = data["MonitoredStopVisit"] as Array<Dictionary>?;
        if (visits != null) {
            while (lineCount < Constants.LINES_TO_SHOW && index < visits.size()) {
                var visit = visits[index];

                var journey = visit["MonitoredVehicleJourney"] as Dictionary<String, String or Number or Boolean or Dictionary>;
                var call = (journey["MonitoredCall"] as Dictionary<String, String or Number or Boolean or Dictionary>);
                var expectedDepartureTimeString = call["ExpectedDepartureTime"] as String;
                var busAtStop = call["VehicleAtStop"] as Boolean;
                var lineName = journey["PublishedLineName"] as String;
                var destinationName = journey["DestinationName"] as String;

                var expectedDepartureTime = Utils.parseIsoDate(expectedDepartureTimeString);
                if (expectedDepartureTime != null) {
                    var timeDifference = expectedDepartureTime.compare(Time.now());
                    if (timeDifference >= 0) {
                        var waitTime = (timeDifference / 60).format("%02d") + ":" + (timeDifference % 60).format("%02d");

                        if (busAtStop) {
                            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
                        } else {
                            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
                        }
                        dc.drawText(columnsX[0], cursorY, Graphics.FONT_SYSTEM_TINY, waitTime + ": " + lineName + " (" + destinationName + ")", Graphics.TEXT_JUSTIFY_LEFT);

                        cursorY += lineHeight + Constants.VERTICAL_SPACE;

                        lineCount++;
                    }
                }

                index++;
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
            dc.drawText(columnsX[0], cursorY, Graphics.FONT_SYSTEM_TINY, errorMessage, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

   (:roundScreen)
    private function calculateViewPortBoundaryX(y as Number, fontHeight as Number, screenWidth as Number, screenHeight as Number, rightSide as Boolean) as Number {
        var circleOriginX = screenWidth / 2;
        var circleOriginY = screenHeight / 2;

        if (y > circleOriginY) {
            y += fontHeight;
        }
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