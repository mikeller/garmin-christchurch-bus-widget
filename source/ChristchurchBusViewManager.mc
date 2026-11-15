import Toybox.Lang;
import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Timer;

class ChristchurchBusViewManager {
    private var reader as ChristchurchBusDataReader;
    private var behaviourDelegate as WatchUi.BehaviorDelegate;
    private var currentView as WatchUi.View;
    private var currentPageTitle as String = Constants.NO_STOPS_STRING;
    private var currentDistance as String?;
    private var favourites as Array<Dictionary> = [] as Array<Dictionary>;
    private var pages as Array<Dictionary> = [] as Array<Dictionary>;
    private var currentStopIndex as Number = 0;
    private var savedStopId as Number?;
    private var rotation as Number = 0;
    private var requestsThisCycle as Number = 0;
    private var cycleStartedAt as Number = -1;
    private var started as Boolean = false;
    private var nearbyLocation as NearbyLocation?;
    (:nearby) private var tileReader as ChristchurchBusTileReader = new ChristchurchBusTileReader();
    (:nearby) private var nearbyEntries as Array = [] as Array;
    (:nearby) private var favouriteEntries as Array = [] as Array;
    (:nearby) private var fixAt as Number = 0;
    (:nearby) private var nearbyStatus as String?;
    (:nearby) private var tileLat as Number?;
    (:nearby) private var tileLon as Number?;
    private var retryTimer as Timer.Timer = new Timer.Timer();
    private var retryIndex as Number = -1;
    private var refreshTimer as Timer.Timer = new Timer.Timer();
    private var delayedRefreshRequested as Boolean = false;

    function initialize(stops as Array<Dictionary>?) {
        if (stops != null) {
            favourites = stops;
        }
        for (var i = 0; i < favourites.size(); i++) {
            pages.add(favourites[i]);
        }
        var lastId = ChristchurchBusDataCache.getLastStop(favourites);
        savedStopId = lastId;
        if (lastId != null) {
            for (var i = 0; i < pages.size(); i++) {
                if (pages[i]["stopId"] == lastId) {
                    currentStopIndex = i;
                    break;
                }
            }
        }
        reader = new ChristchurchBusDataReader();
        behaviourDelegate = new ChristchurchBusBehaviorDelegate(method(:manualRefresh), method(:nextStop));
        currentView = new BaseChristchurchBusView(currentPageTitle, false, null, null);
        if (ChristchurchBusAppProperties.nearbyEnabled()) {
            setNearbyStatus(WatchUi.loadResource(Rez.Strings.Locating) as String);
            showEmptyState(WatchUi.loadResource(Rez.Strings.Locating) as String, null);
            nearbyLocation = new NearbyLocation();
            (nearbyLocation as NearbyLocation).start(method(:onNearbyLocation));
        }
        if (pages.size() > 0) {
            displayBusesForCurrentStop();
        } else if (!ChristchurchBusAppProperties.nearbyEnabled()) {
            showDisabledState();
        }
        started = true;
    }

    function getInitialView() as [ Views ] or [ Views, InputDelegates ] {
        return [currentView, behaviourDelegate] as [Views, InputDelegates];
    }

    function stop() as Void {
        retryTimer.stop();
        refreshTimer.stop();
        if (nearbyLocation != null) {
            (nearbyLocation as NearbyLocation).stop();
            nearbyLocation = null;
        }
    }

    private function switchView() as Void {
        if (started) {
            WatchUi.switchToView(currentView, behaviourDelegate, WatchUi.SLIDE_IMMEDIATE);
        }
    }

    private function showEmptyState(title as String, hint as String?) as Void {
        if (pages.size() == 0) {
            currentView = newEmptyState(title, hint);
            switchView();
        } else {
            Utils.log(title + (hint == null ? "" : ": " + hint));
            displayBusesForCurrentStop();
        }
    }

    (:nearby)
    private function newEmptyState(title as String, hint as String?) as WatchUi.View {
        return new NearbyStatusView(title, hint);
    }

    (:noNearby)
    private function newEmptyState(title as String, hint as String?) as WatchUi.View {
        // Excluded devices keep their original No stops! page and layout.
        return new BaseChristchurchBusView(title, false, hint, null);
    }

    (:nearby)
    private function showDisabledState() as Void {
        showEmptyState(Constants.NO_STOPS_STRING,
            WatchUi.loadResource(Rez.Strings.ConfigureStopsHint) as String);
    }

    (:nearby)
    private function setNearbyStatus(status as String?) as Void {
        nearbyStatus = status;
    }

    (:noNearby)
    private function setNearbyStatus(status as String?) as Void {}

    (:noNearby)
    private function showDisabledState() as Void {
        showEmptyState(Constants.NO_STOPS_STRING, null);
    }

    function nextStop() as Void {
        if (pages.size() == 0) {
            return;
        }
        currentStopIndex = (currentStopIndex + 1) % pages.size();
        ChristchurchBusDataCache.setLastStop(pages[currentStopIndex]["stopId"] as Number,
            pages[0]["stopId"] as Number);
    }

    function manualRefresh() as Void {
        refreshNearby(true);
        displayBusesForCurrentStop();
    }

    (:noNearby)
    private function refreshNearby(force as Boolean) as Void {}

    (:nearby)
    private function refreshNearby(force as Boolean) as Void {
        if (nearbyLocation == null) {
            return;
        }
        (nearbyLocation as NearbyLocation).refresh();
        if (tileReader.isPending()) {
            var pendingCoords = (nearbyLocation as NearbyLocation).getCoordinates();
            if (pendingCoords != null && tileLat != null && tileLon != null &&
                NearbyStopMaths.movedMoreThan(pendingCoords[0], pendingCoords[1],
                    tileLat as Number, tileLon as Number, 100)) {
                fixAt = 0;
                if (pages.size() > 0) {
                    displayBusesForCurrentStop();
                }
            }
            requestDelayedRefresh();
            return;
        }
        var coords = (nearbyLocation as NearbyLocation).getCoordinates();
        if (coords == null) {
            return;
        }
        var lat = coords[0];
        var lon = coords[1];
        if (!force && tileLat != null && tileLon != null &&
            !NearbyStopMaths.movedMoreThan(lat, lon, tileLat as Number, tileLon as Number, 100)) {
            return;
        }
        if (tileLat != null && tileLon != null &&
            NearbyStopMaths.movedMoreThan(lat, lon, tileLat as Number, tileLon as Number, 100)) {
            // The previous distance belongs to the old fix. Hide it while
            // discovery at the new position is still in flight.
            fixAt = 0;
            if (pages.size() > 0) {
                displayBusesForCurrentStop();
            }
        }
        // This session uses exactly one location acquisition. A manual refresh
        // recomputes from that fix, but never starts a second Position listener.
        var tile = NearbyStopMaths.tileId(lat, lon);
        tileLat = lat;
        tileLon = lon;
        if (!tileReader.getTile(tile[0], tile[1], method(:onTile))) {
            tileLat = null;
            tileLon = null;
            requestDelayedRefresh();
        }
    }

    (:nearby)
    function onNearbyLocation() as Void {
        if (nearbyLocation != null && (nearbyLocation as NearbyLocation).getState() == NearbyLocation.FIX) {
            refreshNearby(false);
        } else {
            clearNearby();
            setNearbyStatus(WatchUi.loadResource(Rez.Strings.NearbyUnavailable) as String);
            showEmptyState(WatchUi.loadResource(Rez.Strings.NearbyUnavailable) as String,
                WatchUi.loadResource(Rez.Strings.NearbyLocationHint) as String);
        }
    }

    (:noNearby)
    function onNearbyLocation() as Void {}

    (:nearby)
    private function clearNearby() as Void {
        nearbyEntries = [];
        favouriteEntries = [];
        fixAt = 0;
        rebuildPages();
    }

    (:nearby)
    function onTile(result as Number, stops as Array?, stale as Boolean) as Void {
        if (nearbyLocation == null || (nearbyLocation as NearbyLocation).getState() != NearbyLocation.FIX) {
            return;
        }
        var latest = (nearbyLocation as NearbyLocation).getCoordinates();
        if (latest == null || tileLat == null || tileLon == null ||
            NearbyStopMaths.movedMoreThan(latest[0], latest[1],
                tileLat as Number, tileLon as Number, 100)) {
            fixAt = 0;
            tileLat = null;
            tileLon = null;
            if (pages.size() > 0) {
                displayBusesForCurrentStop();
            }
            requestDelayedRefresh();
            return;
        }
        if (result != ChristchurchBusTileReader.READY || stops == null) {
            tileLat = null;
            tileLon = null;
            clearNearby();
            if (result == ChristchurchBusTileReader.NO_STOPS) {
                setNearbyStatus(WatchUi.loadResource(Rez.Strings.NoStopsNearby) as String);
                showEmptyState(WatchUi.loadResource(Rez.Strings.NoStopsNearby) as String, null);
            } else {
                setNearbyStatus(WatchUi.loadResource(Rez.Strings.NearbyUnavailable) as String);
                showEmptyState(WatchUi.loadResource(Rez.Strings.NearbyUnavailable) as String,
                    WatchUi.loadResource(Rez.Strings.NearbyTileHint) as String);
            }
            return;
        }
        if (stops.size() == 0) {
            clearNearby();
            setNearbyStatus(WatchUi.loadResource(Rez.Strings.NoStopsNearby) as String);
            showEmptyState(WatchUi.loadResource(Rez.Strings.NoStopsNearby) as String, null);
            return;
        }
        var codes = [] as Array<Number>;
        for (var i = 0; i < favourites.size(); i++) {
            codes.add(favourites[i]["stopId"] as Number);
        }
        var split = NearbyStopMaths.nearestSplit(stops, tileLat as Number, tileLon as Number,
            codes, NearbyStopMaths.NEARBY_COUNT);
        nearbyEntries = split[0] as Array;
        setNearbyStatus(null);
        favouriteEntries = stale ? [] as Array : split[1] as Array;
        fixAt = stale ? 0 : (nearbyLocation as NearbyLocation).getFixTime();
        var saved = [] as Array;
        for (var i = 0; i < nearbyEntries.size(); i++) {
            var entry = nearbyEntries[i] as Array;
            saved.add([entry[0], NearbyPageNames.displayName(entry, nearbyEntries), entry[2]]);
        }
        ChristchurchBusDataCache.setNearbyStops(saved, fixAt);
        rebuildPages();
    }

    (:nearby)
    private function rebuildPages() as Void {
        var selectedId = pages.size() > 0 ? pages[currentStopIndex]["stopId"] : savedStopId;
        savedStopId = null;
        var codes = [] as Array<Number>;
        for (var i = 0; i < favourites.size(); i++) {
            codes.add(favourites[i]["stopId"] as Number);
        }
        var ordered = NearbyStopMaths.buildPageOrder(codes, nearbyEntries,
            favouriteEntries, ChristchurchBusAppProperties.favouritesBeforeNearby());
        var newPages = [] as Array<Dictionary>;
        for (var i = 0; i < ordered.size(); i++) {
            var row = ordered[i] as Array;
            var code = row[NearbyStopMaths.PAGE_CODE] as Number;
            if (row[NearbyStopMaths.PAGE_IS_FAVOURITE] as Boolean) {
                for (var j = 0; j < favourites.size(); j++) {
                    if (favourites[j]["stopId"] == code) {
                        newPages.add({"stopId" => code, "displayName" => favourites[j]["displayName"],
                            "metres" => row[NearbyStopMaths.PAGE_METRES]});
                        break;
                    }
                }
            } else {
                var entry = null;
                for (var j = 0; j < nearbyEntries.size(); j++) {
                    if ((nearbyEntries[j] as Array)[0] == code) {
                        entry = nearbyEntries[j] as Array;
                        break;
                    }
                }
                newPages.add({"stopId" => code,
                    "displayName" => NearbyPageNames.displayName(entry as Array, nearbyEntries),
                    "metres" => row[NearbyStopMaths.PAGE_METRES], "nearby" => true});
            }
        }
        pages = newPages;
        currentStopIndex = 0;
        for (var i = 0; i < pages.size(); i++) {
            if (pages[i]["stopId"] == selectedId) {
                currentStopIndex = i;
                break;
            }
        }
        if (pages.size() > 0) {
            displayBusesForCurrentStop();
        }
    }

    function displayBusesForCurrentStop() as Void {
        if (pages.size() == 0) {
            return;
        }
        var stop = pages[currentStopIndex];
        var id = stop["stopId"] as Number;
        var name = stop["displayName"] as String?;
        currentPageTitle = name == null || name == "" ? id.toString() : name as String;
        currentDistance = distanceForStop(stop);
        currentView = new BaseChristchurchBusView(currentPageTitle, false, codeSubtitle(stop), currentDistance);
        switchView();
        refreshBusStopCache(currentStopIndex);
    }

    (:noNearby)
    private function distanceForStop(stop as Dictionary) as String? {
        return null;
    }

    (:noNearby)
    private function codeSubtitle(stop as Dictionary) as String? {
        return null;
    }

    (:nearby)
    private function codeSubtitle(stop as Dictionary) as String? {
        return stop["nearby"] == true ? (stop["stopId"] as Number).toString() : nearbyStatus;
    }

    (:nearby)
    private function distanceForStop(stop as Dictionary) as String? {
        var metres = stop["metres"] as Number?;
        if (metres == null || fixAt == 0 || Time.now().value() - fixAt > 300) {
            return null;
        }
        return " " + NearbyPageNames.distance(metres as Number);
    }

    private function refreshBusStopCache(startIndex as Number) as Void {
        if (pages.size() == 0) {
            return;
        }
        // One visible request and at most seven rotating requests per cycle.
        // Handles are stop ids, stable even when the page order changes.
        var visible = pages[startIndex]["stopId"] as Number;
        var now = Time.now().value();
        if (cycleStartedAt < 0 || now < cycleStartedAt ||
            now - cycleStartedAt >= Constants.REFRESH_DELAY_S) {
            cycleStartedAt = now;
            requestsThisCycle = 0;
        }
        requestPage(startIndex);
        for (var count = 0; count < pages.size() - 1 && requestsThisCycle < 8; count++) {
            var index = (rotation + count) % pages.size();
            if ((pages[index]["stopId"] as Number) != visible) {
                requestPage(index);
            }
        }
        rotation = (rotation + 7) % pages.size();
        Utils.log("Departure requests this cycle: " + requestsThisCycle);
        requestDelayedRefresh();
    }

    private function requestPage(index as Number) as Void {
        if (requestsThisCycle >= 8) {
            return;
        }
        var id = pages[index]["stopId"] as Number;
        if (reader.getBusData(id, id, method(:onBusDataReady))) {
            requestsThisCycle++;
        } else if (retryIndex == -1) {
            retryIndex = index;
            retryTimer.start(method(:onRetryRequest), 1000, false);
        }
    }

    function onRetryRequest() as Void {
        var index = retryIndex;
        retryIndex = -1;
        if (index >= 0 && index < pages.size()) {
            requestPage(index);
        }
    }

    function onBusDataReady(data as Dictionary<String, String or Array>?, handle as Number,
                             requestIsCompleted as Boolean, dataIsStale as Boolean) as Void {
        if (pages.size() > 0 && handle == pages[currentStopIndex]["stopId"]) {
            var subtitle = codeSubtitle(pages[currentStopIndex]);
            currentView = data == null ?
                new BaseChristchurchBusView(currentPageTitle, dataIsStale, subtitle, currentDistance) :
                new ChristchurchBusView(data as Dictionary<String, String or Array>,
                    currentPageTitle, dataIsStale, subtitle, currentDistance);
            switchView();
        }
        if (requestIsCompleted) {
            requestDelayedRefresh();
        }
    }

    private function requestDelayedRefresh() as Void {
        if (!delayedRefreshRequested) {
            delayedRefreshRequested = true;
            refreshTimer.start(method(:onDelayedRefresh), Constants.REFRESH_DELAY_S * 1000, false);
        }
    }

    function onDelayedRefresh() as Void {
        delayedRefreshRequested = false;
        refreshNearby(false);
        refreshBusStopCache(currentStopIndex);
    }
}
