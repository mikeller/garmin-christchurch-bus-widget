import Toybox.Lang;
import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Timer;

// The original favourite-only refresh loop, with stable stop IDs for the
// shared cache's validated last-stop migration. No nearby page machinery.
(:noNearby)
class ChristchurchBusViewManager {
    private var reader as ChristchurchBusDataReader;
    private var behaviourDelegate as WatchUi.BehaviorDelegate;
    private var currentView as WatchUi.View;
    private var currentPageTitle as String = Constants.NO_STOPS_STRING;
    private var stops as Array<Dictionary> = [] as Array<Dictionary>;
    private var currentStopIndex as Number = 0;
    private var started as Boolean = false;
    private var retryTimer as Timer.Timer = new Timer.Timer();
    private var retryIndex as Number = -1;
    private var refreshTimer as Timer.Timer = new Timer.Timer();
    private var delayedRefreshRequested as Boolean = false;

    function initialize(stops as Array<Dictionary>?) {
        if (stops != null) {
            self.stops = stops;
        }
        var lastId = ChristchurchBusDataCache.getLastStop(self.stops);
        if (lastId != null) {
            for (var i = 0; i < self.stops.size(); i++) {
                if (self.stops[i]["stopId"] == lastId) {
                    currentStopIndex = i;
                    break;
                }
            }
        }
        reader = new ChristchurchBusDataReader();
        behaviourDelegate = new ChristchurchBusBehaviorDelegate(
            method(:displayBusesForCurrentStop), method(:nextStop));
        currentView = new BaseChristchurchBusView(currentPageTitle, false, null, null);
        displayBusesForCurrentStop();
        started = true;
    }

    function getInitialView() as [ Views ] or [ Views, InputDelegates ] {
        Utils.log("Initial view loaded.");
        return [currentView, behaviourDelegate] as [Views, InputDelegates];
    }

    function stop() as Void {
        retryTimer.stop();
        refreshTimer.stop();
    }

    private function switchView() as Void {
        WatchUi.switchToView(currentView, behaviourDelegate, WatchUi.SLIDE_IMMEDIATE);
    }

    function nextStop() as Void {
        if (stops.size() == 0) {
            return;
        }
        currentStopIndex = (currentStopIndex + 1) % stops.size();
        ChristchurchBusDataCache.setLastStop(stops[currentStopIndex]["stopId"] as Number,
            stops[0]["stopId"] as Number);
    }

    function displayBusesForCurrentStop() as Void {
        if (stops.size() == 0) {
            return;
        }
        var stop = stops[currentStopIndex];
        var stopId = stop["stopId"] as Number;
        var displayName = stop["displayName"] as String;
        currentPageTitle = "".equals(displayName) ? stopId.toString() : displayName;
        Utils.log("Loading view: " + currentPageTitle + " (" + stopId + ")");
        currentView = new BaseChristchurchBusView(currentPageTitle, false, null, null);
        if (started) {
            switchView();
        }
        refreshBusStopCache(currentStopIndex);
    }

    private function refreshBusStopCache(startIndex as Number) as Void {
        for (var counter = 0; counter < stops.size(); counter++) {
            var index = (startIndex + counter) % stops.size();
            var stopId = stops[index]["stopId"] as Number;
            if (!reader.getBusData(stopId, index, method(:onBusDataReady)) && retryIndex == -1) {
                retryIndex = index;
                retryTimer.start(method(:onRetryRequest), 1000, false);
            }
        }
    }

    function onRetryRequest() as Void {
        var index = retryIndex;
        retryIndex = -1;
        refreshBusStopCache(index);
    }

    function onBusDataReady(data as Dictionary<String, String or Array>?, handle as Number,
                             requestIsCompleted as Boolean, dataIsStale as Boolean) as Void {
        if (handle == currentStopIndex) {
            if (data != null) {
                currentView = new ChristchurchBusView(data, currentPageTitle, dataIsStale, null, null);
            } else {
                currentView = new BaseChristchurchBusView(currentPageTitle, dataIsStale, null, null);
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
        delayedRefreshRequested = false;
        refreshBusStopCache(currentStopIndex);
    }
}
