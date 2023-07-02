import Toybox.Lang;
import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Time.Gregorian;
import Toybox.Timer;

class ChristchurchBusViewManager {
    private var reader as ChristchurchBusDataReader;

    private var behaviourDelegate as WatchUi.BehaviorDelegate;

    private var currentView as WatchUi.View;
    private var currentPageTitle as String = Constants.NO_STOPS_STRING;

    private var stops as Array<Dictionary> = [] as Array<Dictionary>;
    private var currentStopIndex as Number = 0;

    private var started as Boolean = false;

    private var refreshTimer as Timer.Timer = new Timer.Timer();
    private var delayedRefreshRequested as Boolean = false;

    function initialize(stops as Array<Dictionary>) {
        if (stops != null) {
            self.stops = stops;
        }

        reader = new ChristchurchBusDataReader();
        behaviourDelegate = new ChristchurchBusBehaviorDelegate(method(:displayBusesForCurrentStop), method(:nextStop));
        currentView = new BaseChristchurchBusView(currentPageTitle, false);

        displayBusesForCurrentStop();

        started = true;
    }

    function getInitialView() as Array<Views or InputDelegates>? {
        Utils.log("Initial view loaded.");

        return [ currentView, behaviourDelegate ] as Array<Views or InputDelegates>;
    }

    private function switchView () as Void {
        WatchUi.switchToView(currentView, behaviourDelegate, WatchUi.SLIDE_IMMEDIATE);
    }

    function nextStop() as Void {
        currentStopIndex++;
        if (currentStopIndex >= stops.size()) {
            currentStopIndex = 0;
        }
    }

    function displayBusesForCurrentStop() as Void {
        if (stops.size() > 0) {
            var stop = getStop(currentStopIndex);
            var stopId = stop["stopId"] as Number;

            var displayName = stop["displayName"] as String;
            if ("".equals(displayName)) {
                currentPageTitle = "" + stopId;
            } else {
                currentPageTitle = displayName;
            }

            Utils.log("Loading view: " + currentPageTitle + " (" + stopId + ")");

            currentView = new BaseChristchurchBusView(currentPageTitle, false);

            if (started) {
                switchView();
            }

            refreshBusStopCache(currentStopIndex);
        }
    }

    private function refreshBusStopCache(startIndex as Number) as Void {
        for (var counter = 0; counter < stops.size(); counter++) {
            var index = (startIndex + counter) % stops.size();
            var stop = getStop(index);
            var stopId = stop["stopId"] as Number;

            reader.getBusData(stopId, index, method(:onBusDataReady));
        }
    }

    private function getStop(index as Number) as Dictionary<String, Number or String or Boolean> {
        return stops[index] as Dictionary<String, Number or String or Boolean>;
    }

    function onBusDataReady(data as Dictionary<String, String or Array>?, handle as Number, requestIsCompleted as Boolean, dataIsStale as Boolean) as Void {
        if (handle == currentStopIndex) {
            if (data != null) {
                currentView = new ChristchurchBusView(data, currentPageTitle, dataIsStale);
            } else {
                currentView = new BaseChristchurchBusView(currentPageTitle, dataIsStale);
            }

            switchView();
        }

        if (requestIsCompleted) {
            requestDelayedRefresh();
        }
    }

    private function requestDelayedRefresh() as Void {
        if (!delayedRefreshRequested) {
            Utils.log("Delayed refresh requested.");

            refreshTimer.start(method(:onDelayedRefresh), Constants.REFRESH_DELAY_S * 1000, false);

            delayedRefreshRequested = true;
        }
    }

    function onDelayedRefresh() as Void {
        Utils.log("Delayed refresh running.");

        refreshBusStopCache(currentStopIndex);
    }
}
