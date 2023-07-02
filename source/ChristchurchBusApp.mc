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

    function getGlanceView() as Array<GlanceView>? {
        return [new ChristchurchBusGlanceView(stops.size() > 0 ? stops[0] : null)] as Array<GlanceView>;
    }

    (:typecheck(disableGlanceCheck))
    function getInitialView() as Array<Views or InputDelegates>? {
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
        Utils.log("App Stopped.");
    }
}

function getApp() as ChristchurchBusApp {
    return Application.getApp() as ChristchurchBusApp;
}
