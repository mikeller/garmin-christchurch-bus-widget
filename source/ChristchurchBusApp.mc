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

    function getGlanceView() as [ GlanceView ] or [ GlanceView, GlanceViewDelegate ] or Null {
        var lastId = ChristchurchBusDataCache.getLastStop(stops);
        var stopIndex = 0;
        var found = false;
        for (var i = 0; i < stops.size(); i++) {
            if (stops[i]["stopId"] == lastId) {
                stopIndex = i;
                found = true;
                break;
            }
        }
        if (!found && lastId != null && ChristchurchBusAppProperties.nearbyEnabled()) {
            var nearby = lastNearbyGlanceStop(lastId as Number);
            if (nearby != null) {
                return [new ChristchurchBusGlanceView(nearby)] as [GlanceView];
            }
        }
        return [new ChristchurchBusGlanceView(stops.size() > 0 ? stops[stopIndex] : null)] as [GlanceView];
    }

    (:nearby, :glance)
    private function lastNearbyGlanceStop(stopId as Number) as Dictionary? {
        return ChristchurchBusDataCache.getNearbyStop(stopId);
    }

    (:noNearby, :glance)
    private function lastNearbyGlanceStop(stopId as Number) as Dictionary? {
        return null;
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
        }
        Utils.log("App Stopped.");
    }
}

function getApp() as ChristchurchBusApp {
    return Application.getApp() as ChristchurchBusApp;
}
