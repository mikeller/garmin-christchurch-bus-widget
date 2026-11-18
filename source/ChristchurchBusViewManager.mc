import Toybox.Lang;
import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Timer;
import Toybox.System;

(:nearby)
class ChristchurchBusViewManager {
    private static const DEPARTURE_TIMEOUT_S = 15;
    private var reader as ChristchurchBusDataReader;
    private var behaviourDelegate as WatchUi.BehaviorDelegate;
    private var currentView as WatchUi.View;
    private var currentPageTitle as String = Constants.NO_STOPS_STRING;
    private var currentTitleFromTile as Boolean = false;
    private var currentDistance as String?;
    private var favourites as Array<Dictionary> = [] as Array<Dictionary>;
    private var pages as Array<Dictionary> = [] as Array<Dictionary>;
    private var currentStopIndex as Number = 0;
    private var savedStopId as Number?;
    private var initialPagesBuilt as Boolean = false;
    private var retainedNearby as Number?;
    private var lastRequestAt as Dictionary<Number, Number> = {} as Dictionary<Number, Number>;
    private var updateFailed as Dictionary<Number, Boolean> = {} as Dictionary<Number, Boolean>;
    private var requestsThisCycle as Number = 0;
    private var cycleStartedAt as Number = -1;
    private var started as Boolean = false;
    private var nearbyLocation as NearbyLocation?;
    (:nearby) private var tileReader as ChristchurchBusTileReader = new ChristchurchBusTileReader();
    (:nearby) private var nearbyEntries as Array = [] as Array;
    (:nearby) private var favouriteEntries as Array = [] as Array;
    (:nearby) private var fixAt as Number = 0;
    private var dataLat as Number?;
    private var dataLon as Number?;
    private var selectedLat as Number?;
    private var selectedLon as Number?;
    private var selectedAt as Number = -1;
    private var dataFixStale as Boolean = false;
    private var dataPending as Boolean = false;
    (:nearby) private var nearbyStatus as String?;
    (:nearby) private var slotState as Number = NearbyPageOrder.LOCATING;
    (:nearby) private var slotReason as Number = NearbyUnavailableReason.NO_FIX;
    (:nearby) private var slotCode as Number = 0;
    (:nearby) private var tileRetryAt as Number = 0;
    (:nearby) private var tileLat as Number?;
    (:nearby) private var tileLon as Number?;
    (:nearby) private var lastTileRequestAt as Number = -1;
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
        savedStopId = ChristchurchBusDataCache.getLastFavouriteForWidget(favourites);
        reader = new ChristchurchBusDataReader();
        behaviourDelegate = new ChristchurchBusBehaviorDelegate(method(:manualRefresh), method(:nextStop));
        currentView = new BaseChristchurchBusView(currentPageTitle, false, null, null);
        if (ChristchurchBusAppProperties.nearbyEnabled()) {
            setNearbyStatus(WatchUi.loadResource(Rez.Strings.Locating) as String);
            nearbyLocation = new NearbyLocation();
            // Load the stored/getInfo fix before the first nearby page build.
            (nearbyLocation as NearbyLocation).start(method(:onNearbyLocation));
            initializeNearbyPages();
        } else {
            // There is no rebuild when nearby is off; log the single-page
            // decision too, so debug runs can distinguish a disabled setting.
            logPageDecision();
        }
        if (pages.size() > 0 && !ChristchurchBusAppProperties.nearbyEnabled()) {
            displayBusesForCurrentStop();
        } else if (!ChristchurchBusAppProperties.nearbyEnabled()) {
            showDisabledState();
        }
        started = true;
    }

    (:nearby)
    private function initializeNearbyPages() as Void {
        ChristchurchBusDataCache.discardInvalidNearbyResult();
        rebuildPages();
    }

    (:noNearby)
    private function initializeNearbyPages() as Void {}

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

    function viewHidden(view as WatchUi.View) as Void {
        // Page switches replace currentView before the previous page hides.
        // Only hiding the current page means that the widget left the screen.
        if (view == currentView && nearbyLocation != null) {
            (nearbyLocation as NearbyLocation).stop();
        }
    }

    function viewShown(view as WatchUi.View) as Void {
        if (view == currentView && nearbyLocation != null &&
            (nearbyLocation as NearbyLocation).getState() == NearbyLocation.IDLE) {
            (nearbyLocation as NearbyLocation).start(method(:onNearbyLocation));
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
        var oldIndex = currentStopIndex;
        currentStopIndex = nextPageIndex(currentStopIndex, pages.size());
        if (retainedNearby != null && pages[oldIndex]["stopId"] == retainedNearby) {
            var nextPage = pages[currentStopIndex];
            pages.remove(pages[oldIndex]);
            currentStopIndex = NearbyPageOrder.preserve(nextPage, pages, 0);
            retainedNearby = null;
        }
        logSelectDecision(oldIndex, currentStopIndex, pages.size());
        ChristchurchBusDataCache.rememberFavouritePage(pages[currentStopIndex], favourites);
    }

    (:nearby)
    private function nextPageIndex(index as Number, count as Number) as Number {
        return NearbyPageOrder.nextIndex(index, count);
    }

    (:noNearby)
    private function nextPageIndex(index as Number, count as Number) as Number {
        return (index + 1) % count;
    }

    (:nearby, :debug)
    private function logSelectDecision(oldIndex as Number, newIndex as Number,
                                       count as Number) as Void {
        System.println("Nearby select: old=" + oldIndex + ", new=" + newIndex +
            ", pages=" + count);
    }

    (:nearby, :release)
    private function logSelectDecision(oldIndex as Number, newIndex as Number,
                                       count as Number) as Void {}

    (:noNearby)
    private function logSelectDecision(oldIndex as Number, newIndex as Number,
                                       count as Number) as Void {}

    (:nearby, :debug)
    private function logPageDecision() as Void {
        System.println("Nearby pages: favourites=" + favourites.size() +
            ", enabled=" + ChristchurchBusAppProperties.nearbyEnabled() +
            ", count=" + ChristchurchBusAppProperties.nearbyStopsToShow() +
            ", slot=" + slotState + ", pages=" + pages.size() +
            ", index=" + currentStopIndex);
    }

    (:nearby, :release)
    private function logPageDecision() as Void {}

    (:noNearby)
    private function logPageDecision() as Void {}

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
        var coords = (nearbyLocation as NearbyLocation).getCoordinates();
        if (coords == null) {
            return;
        }
        var lat = coords[0];
        var lon = coords[1];
        var tile = NearbyStopMaths.tileId(lat, lon);
        var oldTile = tileLat == null || tileLon == null ? null :
            NearbyStopMaths.tileId(tileLat as Number, tileLon as Number);
        var sameTile = oldTile != null && tile[0] == (oldTile as Array)[0] &&
            tile[1] == (oldTile as Array)[1];
        if (tileReader.isPending()) {
            dataPending = true;
            if (pages.size() > 0) {
                displayBusesForCurrentStop();
            }
            requestDelayedRefresh();
            return;
        }
        if (sameTile && fixAt != 0) {
            // A tile has at most 15 validated rows. Read it once per accepted
            // fix, not onUpdate, to refresh distances without a network call.
            var cached = tileReader.readCache(tile[0].toString() + "," +
                tile[1].toString(), false);
            if (cached != null) {
                var rows = (cached as Dictionary)["s"] as Array;
                if (force || NearbyRefreshPolicy.shouldRefresh(lat, lon, selectedLat,
                    selectedLon, selectedAt, Time.now().value())) {
                    onTile(ChristchurchBusTileReader.READY,
                        NearbyServiceContext.context(cached as Dictionary, true), false);
                } else if (NearbyRefreshPolicy.shouldUpdateDistances(lat, lon,
                    (nearbyLocation as NearbyLocation).getFixTime(), dataLat, dataLon,
                    fixAt, dataPending)) {
                    refreshDistances(rows, lat, lon);
                }
                return;
            }
        }
        dataPending = fixAt != 0;
        if (pages.size() > 0 && dataPending) {
            displayBusesForCurrentStop();
        }
        if (!force && Time.now().value() < tileRetryAt) {
            return;
        }
        tileLat = lat;
        tileLon = lon;
        if (tileReader.getTile(tile[0], tile[1], method(:onTile))) {
            lastTileRequestAt = Time.now().value();
        } else {
            requestDelayedRefresh();
        }
    }

    // Update existing distances from the same validated tile. Selection is
    // unchanged until the movement/time policy requests a full nearest split.
    private function refreshDistances(rows as Array, lat as Number, lon as Number) as Void {
        dataPending = false;
        for (var i = 0; i < pages.size(); i++) {
            var page = pages[i];
            if (page["metres"] == null) {
                continue;
            }
            var id = page["stopId"] as Number?;
            var metres = NearbyStopMaths.metresForCode(rows, id as Number, lat, lon);
            if (metres == null) {
                dataPending = true; // Retained stop is outside this tile.
            } else {
                page["metres"] = metres;
            }
        }
        for (var n = 0; n < nearbyEntries.size(); n++) {
            var entry = nearbyEntries[n] as Array;
            for (var j = 0; j < rows.size(); j++) {
                var row = rows[j] as Array;
                if (entry[NearbyStopMaths.ENTRY_CODE] == row[NearbyStopMaths.STOP_CODE]) {
                    entry[NearbyStopMaths.ENTRY_METRES] = NearbyStopMaths.approxMetres(
                        row[NearbyStopMaths.STOP_LAT_E5] as Number,
                        row[NearbyStopMaths.STOP_LON_E5] as Number, lat, lon);
                    break;
                }
            }
        }
        dataLat = lat;
        dataLon = lon;
        fixAt = (nearbyLocation as NearbyLocation).getFixTime();
        dataFixStale = (nearbyLocation as NearbyLocation).isStale();
        if (pages.size() > 0) {
            displayBusesForCurrentStop();
        }
    }

    (:nearby)
    function onNearbyLocation() as Void {
        if (nearbyLocation != null && (nearbyLocation as NearbyLocation).getState() == NearbyLocation.FIX) {
            if (slotState == NearbyPageOrder.LOCATING ||
                slotState == NearbyPageOrder.UNAVAILABLE ||
                slotState == NearbyPageOrder.EMPTY) {
                slotState = NearbyPageOrder.WAITING_TILE;
                rebuildPages();
            }
            refreshNearby(fixAt == 0);
            if (started) {
                // The current view reads fix age while drawing. A fix within
                // the same 100 m area need not recreate any pages or rows.
                WatchUi.requestUpdate();
            }
        } else {
            clearNearby();
            slotState = NearbyPageOrder.UNAVAILABLE;
            slotReason = (nearbyLocation as NearbyLocation).getFailureReason();
            setNearbyStatus(WatchUi.loadResource(Rez.Strings.NearbyUnavailable) as String);
            rebuildPages();
        }
    }

    (:noNearby)
    function onNearbyLocation() as Void {}

    (:nearby)
    private function clearNearby() as Void {
        nearbyEntries = [];
        favouriteEntries = [];
        fixAt = 0;
        dataLat = null;
        dataLon = null;
        selectedLat = null;
        selectedLon = null;
        selectedAt = -1;
        dataPending = false;
    }

    (:nearby)
    function onTile(result as Number, context as Dictionary?, stale as Boolean) as Void {
        var stops = context == null ? null : context["s"] as Array;
        if (nearbyLocation == null || (nearbyLocation as NearbyLocation).getState() != NearbyLocation.FIX) {
            return;
        }
        var latest = (nearbyLocation as NearbyLocation).getCoordinates();
        var latestTile = latest == null ? null : NearbyStopMaths.tileId(latest[0], latest[1]);
        var pendingTile = tileLat == null || tileLon == null ? null :
            NearbyStopMaths.tileId(tileLat as Number, tileLon as Number);
        if (latest == null || pendingTile == null ||
            (latestTile as Array)[0] != (pendingTile as Array)[0] ||
            (latestTile as Array)[1] != (pendingTile as Array)[1]) {
            dataPending = true;
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
                slotState = NearbyPageOrder.EMPTY;
                slotCode = tileReader.getFailureCode();
            } else {
                slotState = NearbyPageOrder.UNAVAILABLE;
                slotCode = tileReader.getFailureCode();
                slotReason = NearbyUnavailableReason.forTile(slotCode,
                    false);
            }
            tileRetryAt = Time.now().value() + 30;
            rebuildPages();
            requestDelayedRefresh();
            return;
        }
        if (stops.size() == 0) {
            clearNearby();
            slotState = NearbyPageOrder.EMPTY;
            slotCode = 0;
            rebuildPages();
            return;
        }
        var codes = [] as Array<Number>;
        for (var i = 0; i < favourites.size(); i++) {
            codes.add(favourites[i]["stopId"] as Number);
        }
        var split = NearbyCoverageSelection.select([context as Dictionary],
            latest[0], latest[1], codes, ChristchurchBusAppProperties.nearbyStopsToShow());
        nearbyEntries = split[0] as Array;
        slotState = nearbyEntries.size() == 0 ? NearbyPageOrder.EMPTY : NearbyPageOrder.READY;
        slotCode = 0;
        tileRetryAt = 0;
        setNearbyStatus(null);
        favouriteEntries = stale ? [] as Array : split[1] as Array;
        fixAt = (nearbyLocation as NearbyLocation).getFixTime();
        dataLat = latest[0];
        dataLon = latest[1];
        selectedLat = latest[0];
        selectedLon = latest[1];
        selectedAt = Time.now().value();
        dataFixStale = (nearbyLocation as NearbyLocation).isStale();
        dataPending = false;
        if (pages.size() > currentStopIndex &&
            pages[currentStopIndex]["nearby"] == true) {
            var selectedPage = pages[currentStopIndex];
            var stillNearby = false;
            for (var n = 0; n < nearbyEntries.size(); n++) {
                if ((nearbyEntries[n] as Array)[NearbyStopMaths.ENTRY_CODE] ==
                    selectedPage["stopId"]) {
                    stillNearby = true;
                    break;
                }
            }
            if (!stillNearby) {
                var retainedMetres = NearbyStopMaths.metresForCode(stops,
                    selectedPage["stopId"] as Number, latest[0], latest[1]);
                if (retainedMetres == null) {
                    dataPending = true; // Old stop is absent from the new tile.
                } else {
                    selectedPage["metres"] = retainedMetres;
                }
            }
        }
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
        var oldIndex = currentStopIndex;
        var oldPage = initialPagesBuilt && pages.size() > oldIndex ? pages[oldIndex] : null;
        // The persisted favourite is used exactly once at startup, never to
        // choose the current page after a live location or tile update.
        var selected = savedStopId;
        savedStopId = null;
        var codes = [] as Array<Number>;
        for (var i = 0; i < favourites.size(); i++) {
            codes.add(favourites[i]["stopId"] as Number);
        }
        var before = ChristchurchBusAppProperties.favouritesBeforeNearby();
        var ordered = NearbyPageOrder.build(codes, nearbyEntries, favouriteEntries, before, slotState);
        var newPages = [] as Array<Dictionary>;
        for (var i = 0; i < ordered.size(); i++) {
            var row = ordered[i] as Array;
            var code = row[NearbyStopMaths.PAGE_CODE] as Number?;
            if (code == null) {
                newPages.add({"nearbySlot" => true});
                continue;
            }
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
        var fallback = NearbyPageOrder.initialIndex(ordered, favourites.size(), before);
        if (!initialPagesBuilt && selected != null) {
            // Startup only: locate the favourite before accepting live fixes.
            oldPage = {"stopId" => selected};
        }
        var chosenIndex = NearbyPageOrder.preserve(oldPage, newPages, fallback);
        if (started && oldPage != null && oldPage["nearby"] == true) {
            if (chosenIndex < 0) {
                // Keep a dropped nearby page visible only until Select.
                var insertAt = oldIndex < newPages.size() ? oldIndex : newPages.size();
                newPages.add(oldPage as Dictionary);
                for (var shift = newPages.size() - 1; shift > insertAt; shift--) {
                    newPages[shift] = newPages[shift - 1];
                }
                newPages[insertAt] = oldPage as Dictionary;
                retainedNearby = oldPage["stopId"] as Number;
                chosenIndex = insertAt;
            } else {
                retainedNearby = null;
            }
        }
        pages = newPages;
        currentStopIndex = chosenIndex;
        initialPagesBuilt = true;
        logPageChange(oldPage, oldIndex, pages.size() > 0 ? pages[currentStopIndex] : null,
            currentStopIndex);
        logPageDecision();
        if (pages.size() > 0) {
            displayBusesForCurrentStop();
        } else if (slotState == NearbyPageOrder.WAITING_TILE) {
            currentView = new NearbyStatusView(
                WatchUi.loadResource(Rez.Strings.LoadingNearbyStops) as String, null);
            switchView();
        }
    }

    (:debug)
    private function logPageChange(before as Dictionary?, beforeIndex as Number,
                                   after as Dictionary?, afterIndex as Number) as Void {
        System.println("Nearby list change: from=" +
            (before == null ? "none" : before["nearbySlot"] == true ? "slot" :
                before["stopId"]) + "@" + beforeIndex + " to=" +
            (after == null ? "none" : after["nearbySlot"] == true ? "slot" :
                after["stopId"]) + "@" + afterIndex);
    }

    (:release)
    private function logPageChange(before as Dictionary?, beforeIndex as Number,
                                   after as Dictionary?, afterIndex as Number) as Void {}

    function displayBusesForCurrentStop() as Void {
        if (pages.size() == 0) {
            return;
        }
        var stop = pages[currentStopIndex];
        if (isSlot(stop)) {
            showSlot();
            return;
        }
        var id = stop["stopId"] as Number;
        var name = stop["displayName"] as String?;
        var cachedRows = isNearbyStop(stop) ? null : cachedTitleRows(id);
        currentTitleFromTile = !isNearbyStop(stop) && cachedRows != null &&
            !NearbyPageNames.hasConfiguredName(name);
        currentPageTitle = isNearbyStop(stop) ? name as String :
            NearbyPageNames.favouriteTitle(name, id, cachedRows,
                WatchUi.loadResource(Rez.Strings.StopCodeFallback) as String);
        currentDistance = distanceForStop(stop);
        var view = new BaseChristchurchBusView(currentPageTitle, updateFailed[id] == true, codeSubtitle(stop),
            pageDistanceSuffix(stop));
        view.setStaleNearbyPosition(stalePosition());
        view.setFixSource(nearbyLocation);
        if (currentDistance != null) {
            view.setDistanceFix(fixAt, dataFixStale || dataPending);
        }
        if (isFavourite(id)) {
            view.setFavouritePage();
        }
        if (isNearbyPage(stop) || currentTitleFromTile) {
            view.setNearbyPage();
        }
        currentView = view;
        switchView();
        // Display a validated cache entry immediately, including an expired
        // entry marked stale, before any network slot or cycle budget is used.
        var fresh = ChristchurchBusDataCache.tryGetCachedData(id, false);
        var cached = fresh != null ? fresh : ChristchurchBusDataCache.tryGetCachedData(id, true);
        if (cached != null) {
            onBusDataReady(cached, id, false, fresh == null);
        }
        refreshBusStopCache(currentStopIndex);
    }

    (:nearby)
    private function cachedTitleRows(id as Number) as Array? {
        return tileReader.cachedRowsFor(id);
    }

    (:noNearby)
    private function cachedTitleRows(id as Number) as Array? {
        return null;
    }

    (:nearby)
    private function stalePosition() as Boolean {
        return ChristchurchBusAppProperties.nearbyEnabled() && nearbyLocation != null &&
            (nearbyLocation as NearbyLocation).isStale();
    }

    (:noNearby)
    private function stalePosition() as Boolean {
        return false;
    }

    (:nearby)
    private function isNearbyStop(stop as Dictionary) as Boolean {
        return stop["nearby"] == true;
    }

    (:noNearby)
    private function isNearbyStop(stop as Dictionary) as Boolean {
        return false;
    }

    (:nearby)
    private function isSlot(stop as Dictionary) as Boolean {
        return stop["nearbySlot"] == true;
    }

    (:noNearby)
    private function isSlot(stop as Dictionary) as Boolean {
        return false;
    }

    (:nearby)
    private function showSlot() as Void {
        var title = slotState == NearbyPageOrder.LOCATING ? Rez.Strings.Locating :
            slotState == NearbyPageOrder.WAITING_TILE ? Rez.Strings.LoadingNearbyStops :
            slotState == NearbyPageOrder.EMPTY ? Rez.Strings.NoStopsNearby : Rez.Strings.NearbyUnavailable;
        var hint = slotState == NearbyPageOrder.UNAVAILABLE ?
            NearbyUnavailableReason.hint(slotReason, slotCode) :
            slotState == NearbyPageOrder.LOCATING ?
                WatchUi.loadResource(Rez.Strings.NearbyWaitingHint) as String :
            slotState == NearbyPageOrder.EMPTY && slotCode == -400 ?
                NearbyUnavailableReason.hint(NearbyUnavailableReason.TILE_CODE, slotCode) : null;
        var status = new NearbyStatusView(WatchUi.loadResource(title) as String, hint);
        status.setStaleNearbyPosition(stalePosition());
        status.setFixSource(nearbyLocation);
        currentView = status;
        switchView();
    }

    (:noNearby)
    private function showSlot() as Void {}

    (:noNearby)
    private function distanceForStop(stop as Dictionary) as String? {
        return null;
    }

    (:noNearby)
    private function codeSubtitle(stop as Dictionary) as String? {
        return null;
    }

    (:noNearby)
    private function pageDistanceSuffix(stop as Dictionary) as String? {
        return null;
    }

    (:nearby)
    private function pageDistanceSuffix(stop as Dictionary) as String? {
        return isNearbyPage(stop) ? currentDistance : null;
    }

    (:noNearby)
    private function isNearbyPage(stop as Dictionary) as Boolean {
        return false;
    }

    (:nearby)
    private function isNearbyPage(stop as Dictionary) as Boolean {
        return stop["nearby"] == true || (stop["metres"] != null && currentDistance != null);
    }

    (:nearby)
    private function codeSubtitle(stop as Dictionary) as String? {
        return null;
    }

    (:nearby)
    private function distanceForStop(stop as Dictionary) as String? {
        var metres = stop["metres"] as Number?;
        if (metres == null || fixAt == 0 || nearbyLocation == null ||
            (nearbyLocation as NearbyLocation).getState() != NearbyLocation.FIX) {
            return null;
        }
        return NearbyPageNames.distance(metres as Number);
    }

    private function refreshBusStopCache(startIndex as Number) as Void {
        if (pages.size() == 0) {
            return;
        }
        var now = Time.now().value();
        if (cycleStartedAt < 0 || now < cycleStartedAt ||
            now - cycleStartedAt >= Constants.REFRESH_DELAY_S) {
            cycleStartedAt = now;
            requestsThisCycle = 0;
        }
        var entries = [] as Array;
        var inFlight = [] as Array<Number>;
        for (var i = 0; i < pages.size(); i++) {
            var id = pages[i]["stopId"] as Number?;
            entries.add([id, isFavourite(id), id == null ? 0 :
                (lastRequestAt[id] as Number?) == null ? 0 : lastRequestAt[id] as Number]);
            if (id != null && reader.isRunning(id as Number)) {
                inFlight.add(id as Number);
            }
        }
        var visible = pages[startIndex]["stopId"] as Number?;
        var stale = visible != null &&
            ChristchurchBusDataCache.tryGetCachedData(visible as Number, false) == null;
        var selected = NearbyDepartureSchedule.choose(entries, startIndex,
            8 - requestsThisCycle, inFlight, stale);
        for (var j = 0; j < selected.size(); j++) {
            requestPage(selected[j], now);
        }
        Utils.log("Departure requests this cycle: " + requestsThisCycle);
        requestDelayedRefresh();
    }

    private function isFavourite(id as Number?) as Boolean {
        if (id != null) {
            for (var i = 0; i < favourites.size(); i++) {
                if (favourites[i]["stopId"] == id) {
                    return true;
                }
            }
        }
        return false;
    }

    private function requestPage(index as Number, now as Number) as Void {
        if (requestsThisCycle >= 8) {
            return;
        }
        var id = pages[index]["stopId"] as Number?;
        if (id == null) {
            return;
        }
        if (reader.getBusData(id as Number, id as Number, method(:onBusDataReady))) {
            requestsThisCycle++;
            lastRequestAt[id as Number] = now;
        } else if (retryIndex == -1) {
            retryIndex = index;
            retryTimer.start(method(:onRetryRequest), 1000, false);
        }
    }

    function onRetryRequest() as Void {
        var index = retryIndex;
        retryIndex = -1;
        if (index >= 0 && index < pages.size()) {
            refreshBusStopCache(index);
        }
    }

    function onBusDataReady(data as Dictionary<String, String or Array>?, handle as Number,
                             requestIsCompleted as Boolean, dataIsStale as Boolean) as Void {
        updateFailed[handle] = NearbyDepartureState.failed(updateFailed[handle] == true,
            requestIsCompleted, dataIsStale, false);
        if (pages.size() > 0 && handle == pages[currentStopIndex]["stopId"]) {
            var stop = pages[currentStopIndex];
            var subtitle = codeSubtitle(stop);
            var suffix = pageDistanceSuffix(stop);
            if (data == null) {
                var base = new BaseChristchurchBusView(currentPageTitle,
                    updateFailed[handle] == true, subtitle, suffix);
                base.setStaleNearbyPosition(stalePosition());
                base.setFixSource(nearbyLocation);
                if (currentDistance != null) {
                    base.setDistanceFix(fixAt, dataFixStale || dataPending);
                }
                if (isFavourite(handle)) {
                    base.setFavouritePage();
                }
                if (isNearbyPage(stop) || currentTitleFromTile) {
                    base.setNearbyPage();
                }
                currentView = base;
            } else {
                var departures = new ChristchurchBusView(data as Dictionary<String, String or Array>,
                    currentPageTitle, updateFailed[handle] == true, subtitle, suffix);
                departures.setStaleNearbyPosition(stalePosition());
                departures.setFixSource(nearbyLocation);
                if (currentDistance != null) {
                    departures.setDistanceFix(fixAt, dataFixStale || dataPending);
                }
                if (isFavourite(handle)) {
                    departures.setFavouritePage();
                }
                if (isNearbyPage(stop) || currentTitleFromTile) {
                    departures.setNearbyPage();
                }
                currentView = departures;
            }
            switchView();
        }
        if (requestIsCompleted) {
            requestDelayedRefresh();
        }
    }

    private function requestDelayedRefresh() as Void {
        if (!delayedRefreshRequested) {
            delayedRefreshRequested = true;
            var visible = pages.size() > 0 ? pages[currentStopIndex]["stopId"] as Number? : null;
            var delay = visible != null && reader.isRunning(visible as Number) ?
                5000 : Constants.REFRESH_DELAY_S * 1000;
            refreshTimer.start(method(:onDelayedRefresh), delay, false);
        }
    }

    function onDelayedRefresh() as Void {
        delayedRefreshRequested = false;
        if (pages.size() > 0) {
            var id = pages[currentStopIndex]["stopId"] as Number?;
            if (id != null && reader.isRunning(id as Number)) {
                var sent = lastRequestAt[id as Number] as Number?;
                if (sent != null && Time.now().value() >= sent as Number &&
                    Time.now().value() - (sent as Number) >= DEPARTURE_TIMEOUT_S &&
                    updateFailed[id as Number] != true) {
                    updateFailed[id as Number] = true;
                    onBusDataReady(ChristchurchBusDataCache.tryGetCachedData(id as Number, true),
                        id as Number, false, true);
                }
            }
        }
        refreshNearby(false);
        refreshBusStopCache(currentStopIndex);
    }
}
