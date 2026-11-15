import Toybox.Lang;
import Toybox.Position;
import Toybox.Time;
import Toybox.Timer;

// Widget-only acquisition; no location request is made from the glance.
(:nearby)
class NearbyLocation {
    static const IDLE = 0;
    static const LOCATING = 1;
    static const FIX = 2;
    static const NO_FIX = 3;

    private var state as Number = IDLE;
    private var latE5 as Number?;
    private var lonE5 as Number?;
    private var fixTimestamp as Number = 0;
    private var timeout as Timer.Timer = new Timer.Timer();
    private var callback as Method?;

    function start(callback as Method) as Void {
        self.callback = callback;
        if (!ChristchurchBusAppProperties.nearbyEnabled()) {
            return;
        }
        stop();
        // A last-known fix can be stale even when it has a good accuracy.
        try {
            if (accept(Position.getInfo())) {
                notify();
                return;
            }
            state = LOCATING;
            timeout.start(method(:onTimeout), 30000, false);
            Position.enableLocationEvents(Position.LOCATION_ONE_SHOT, method(:onLocation));
        } catch (e) {
            finish(false);
        }
    }

    function stop() as Void {
        timeout.stop();
        if (state == LOCATING) {
            disableEvents();
        }
        state = IDLE;
    }

    function getState() as Number {
        return state;
    }

    function getCoordinates() as Array<Number>? {
        if (state != FIX) {
            return null;
        }
        return [latE5 as Number, lonE5 as Number];
    }

    function getFixTime() as Number {
        return fixTimestamp;
    }

    // Re-read the last-known fix without enabling another location listener.
    // This also invalidates a result once the five-minute fix window closes.
    function refresh() as Void {
        if (state != FIX) {
            return;
        }
        try {
            if (!accept(Position.getInfo())) {
                state = NO_FIX;
                notify();
            }
        } catch (e) {
            state = NO_FIX;
            notify();
        }
    }

    private function accept(info as Position.Info?) as Boolean {
        if (info == null || info.position == null || info.accuracy < Position.QUALITY_POOR || info.when == null) {
            return false;
        }
        var age = Time.now().subtract(info.when as Time.Moment).value();
        if (age < 0 || age > 300) {
            return false;
        }
        var degrees = (info.position as Position.Location).toDegrees();
        latE5 = NearbyStopMaths.toE5(degrees[0] as Double);
        lonE5 = NearbyStopMaths.toE5(degrees[1] as Double);
        fixTimestamp = (info.when as Time.Moment).value();
        state = FIX;
        return true;
    }

    function onLocation(info as Position.Info) as Void {
        if (state == LOCATING) {
            finish(accept(info));
        }
    }

    function onTimeout() as Void {
        if (state == LOCATING) {
            finish(false);
        }
    }

    private function finish(hasFix as Boolean) as Void {
        timeout.stop();
        disableEvents();
        state = hasFix ? FIX : NO_FIX;
        notify();
    }

    private function notify() as Void {
        if (callback != null) {
            (callback as Method).invoke();
        }
    }
    private function disableEvents() as Void {
        try {
            Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
        } catch (e) {
            // Permission can be denied while acquisition is in progress.
        }
    }
}

(:noNearby)
class NearbyLocation {
    function start(callback as Method) as Void {}
    function stop() as Void {}
    function refresh() as Void {}
}
