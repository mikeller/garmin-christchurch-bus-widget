import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Application;

(:glance)
class ChristchurchBusApp extends Application.AppBase {
    private var viewManager as ChristchurchBusViewManager?;
    protected var stops as Array<Dictionary> = [] as Array<Dictionary>;

    function initialize() {
        AppBase.initialize();

        var stops = ChristchurchBusAppProperties.getStopsProperty();
        if (stops != null) {
            self.stops = stops;
        }
    }

    (:nearby)
    function getGlanceView() as [ GlanceView ] or [ GlanceView, GlanceViewDelegate ] or Null {
        var selected = selectFavouriteForGlance();
        var nearbyName = null as String?;
        if (selected != null && selected["nearbyAt"] == null &&
            ChristchurchBusAppProperties.nearbyEnabled() &&
            NearbyGlanceTitle.isBlank(selected["displayName"] as String?)) {
            var cached = cachedNearbyTitleStop(selected["stopId"] as Number);
            if (cached != null) {
                nearbyName = cached["displayName"] as String?;
            }
        }
        return [new ChristchurchBusGlanceView(selected, nearbyName)] as [GlanceView];
    }

    (:noNearby)
    function getGlanceView() as [ GlanceView ] or [ GlanceView, GlanceViewDelegate ] or Null {
        var lastId = ChristchurchBusDataCache.getLastStop(stops);
        var stopIndex = 0;
        for (var i = 0; i < stops.size(); i++) {
            if (stops[i]["stopId"] == lastId) {
                stopIndex = i;
                break;
            }
        }
        return [new ChristchurchBusGlanceView(stops.size() > 0 ? stops[stopIndex] : null)] as [GlanceView];
    }

    (:nearby, :glance)
    private function selectFavouriteForGlance() as Dictionary? {
        var lastId = ChristchurchBusDataCache.getLastFavourite(stops);
        var first = stops.size() == 0 && ChristchurchBusAppProperties.nearbyEnabled() ?
            ChristchurchBusDataCache.getNearbyStop(null) : null;
        return NearbyGlanceSelection.select(stops, lastId, first);
    }

    (:nearby, :glance)
    private function cachedNearbyTitleStop(stopId as Number) as Dictionary? {
        return ChristchurchBusDataCache.getNearbyStop(stopId);
    }

    (:typecheck(disableGlanceCheck))
    function getInitialView() as [ Views ] or [ Views, InputDelegates ] {
        if (viewManager == null) {
            viewManager = new ChristchurchBusViewManager(stops);
        }

        return (viewManager as ChristchurchBusViewManager).getInitialView();
    }

    (:typecheck(disableGlanceCheck))
    function onStart(state as Dictionary?) as Void {
        Utils.log("App started.");
    }

    function onStop(state as Dictionary?) as Void {
        if (viewManager != null) {
            (viewManager as ChristchurchBusViewManager).stop();
            // A later start may reuse this AppBase instance. Rebuild the
            // manager so persisted selection and location are read again.
            viewManager = null;
        }
        Utils.log("App Stopped.");
    }

    (:nearby)
    function nearbyViewHidden(view as WatchUi.View) as Void {
        if (viewManager != null) {
            (viewManager as ChristchurchBusViewManager).viewHidden(view);
        }
    }

    (:nearby)
    function nearbyViewShown(view as WatchUi.View) as Void {
        if (viewManager != null) {
            (viewManager as ChristchurchBusViewManager).viewShown(view);
        }
    }
}

function getApp() as ChristchurchBusApp {
    return Application.getApp() as ChristchurchBusApp;
}
