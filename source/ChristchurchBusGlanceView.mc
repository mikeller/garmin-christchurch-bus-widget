import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:glance)
class ChristchurchBusGlanceView extends WatchUi.GlanceView {
    private var stop as Dictionary<String, Number or String>?;
    private var glanceTitle as String = WatchUi.loadResource(Rez.Strings.AppName) as String;

    private var informationFound as Boolean = false;
    private var busAtStop as Boolean = false;
    private var lineName as String = "";
    private var destinationName as String = "";
    private var timeDifference as Number = 0;

    function initialize(stop as Dictionary?) {
        GlanceView.initialize();

        self.stop = stop as Dictionary<String, Number or String>?;
    }

    function onLayout(dc as Dc) as Void {
        try {
            if (stop != null) {
                var stopId = stop["stopId"] as Number;

                var displayName = stop["displayName"] as String;
                if ("".equals(displayName)) {
                    glanceTitle = "" + stopId;
                } else {
                    glanceTitle = displayName;
                }

                var cache = null;
                try {
                     cache = ChristchurchBusDataCache.tryGetCachedData(stopId, true);
                } catch (exception instanceof Exception) {
                    Utils.log("Problem loading cache: " + exception.getErrorMessage());
                    exception.printStackTrace();
                }

                informationFound = false;
                if (cache != null) {
                    var visits = cache["MonitoredStopVisit"] as Array<Dictionary>?;
                    if (visits != null) {
                        var index = 0;
                        while (index < visits.size()) {
                            var visit = visits[index];

                            var expectedDepartureTimeString = visit["ExpectedDepartureTime"] as String;
                            var expectedDepartureTime = Utils.parseIsoDate(expectedDepartureTimeString);
                            if (expectedDepartureTime != null) {
                                timeDifference = expectedDepartureTime.compare(Time.now());
                                if (timeDifference >= 0) {
                                    busAtStop = visit["VehicleAtStop"] as Boolean;
                                    lineName = visit["PublishedLineName"] as String;
                                    destinationName = visit["DestinationName"] as String;
                                    informationFound = true;

                                    break;
                                }
                            }

                            index++;
                        }
                    }
                }
            }
        } catch (exception instanceof UnexpectedTypeException) {
            Utils.log("Data format problem: " + exception.getErrorMessage());
            exception.printStackTrace();
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(0, 0, Graphics.FONT_SYSTEM_TINY, glanceTitle, Graphics.TEXT_JUSTIFY_LEFT);

        var lineHeight = dc.getFontHeight(Graphics.FONT_SYSTEM_TINY);
        var secondLineY = lineHeight + Constants.VERTICAL_SPACE;

        if (informationFound) {
            var waitTime = (timeDifference / 60).format("%02d") + ":" + (timeDifference % 60).format("%02d");

            if (busAtStop) {
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            }

            dc.drawText(0, secondLineY, Graphics.FONT_SYSTEM_TINY, waitTime + ": " + lineName + " (" + destinationName + ")", Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawText(0, secondLineY, Graphics.FONT_SYSTEM_TINY, Constants.NO_INFORMATION_STRING, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }
}
