import Toybox.Lang;
import Toybox.Position;
import Toybox.Time;
import Toybox.Timer;
import Toybox.System;

// Widget-only acquisition; no location request is made from the glance.
(:nearby)
class NearbyLocation {
    static const ACQUISITION_TIMEOUT_MS = 60000;
    static const IDLE = 0;
    static const LOCATING = 1;
    static const FIX = 2;
    static const NO_FIX = 3;

    private var state as Number = IDLE;
    private var latE5 as Number?;
    private var lonE5 as Number?;
    private var fixTimestamp as Number = 0;
    private var fixAgeUnknown as Boolean = false;
    private var stale as Boolean = false;
    private var acquiring as Boolean = false;
    private var timeout as Timer.Timer = new Timer.Timer();
    private var callback as Method?;
    private var failureReason as Number = NearbyUnavailableReason.NO_FIX;

    function start(callback as Method) as Void {
        self.callback = callback;
        if (!ChristchurchBusAppProperties.nearbyEnabled()) {
            return;
        }
        stop();
        // Publish any usable last position before starting a one-shot search.
        try {
            var info = Position.getInfo();
            var usable = accept(info);
            if (usable) {
                notify();
            }
            if (!usable || stale || info.accuracy < Position.QUALITY_POOR) {
                if (!usable) {
                    state = LOCATING;
                }
                acquiring = true;
                timeout.start(method(:onTimeout), ACQUISITION_TIMEOUT_MS, false);
                Position.enableLocationEvents(Position.LOCATION_ONE_SHOT, method(:onLocation));
            }
        } catch (e) {
            // The API does not expose a permission-denied status here. An
            // exception is only a suspected permission/configuration failure.
            failureReason = NearbyUnavailableReason.LOCATION_ERROR;
            finish(false);
        }
    }

    function stop() as Void {
        timeout.stop();
        if (acquiring) {
            disableEvents();
        }
        acquiring = false;
        state = IDLE;
    }

    function getState() as Number {
        return state;
    }

    function getFailureReason() as Number {
        return failureReason;
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

    function isStale() as Boolean {
        return state == FIX && (fixAgeUnknown ||
            Time.now().value() - fixTimestamp > NearbyLocationPolicy.NEARBY_STALE_FIX_SEC);
    }

    // Re-read the last-known fix without enabling another location listener.
    // This also invalidates a result once the five-minute fix window closes.
    function refresh() as Void {
        if (state != FIX) {
            return;
        }
        var aged = isStale();
        if (aged != stale) {
            stale = aged;
            notify();
        }
    }

    private function accept(info as Position.Info?) as Boolean {
        if (info == null || info.position == null) {
            return false;
        }
        var timestamp = null as Number?;
        try {
            if (info.when != null) {
                timestamp = (info.when as Time.Moment).value();
            }
        } catch (e) {
            // Unreadable age still permits a last-known position.
        }
        var decision = NearbyLocationPolicy.decide(info.accuracy, timestamp, Time.now().value());
        if (!decision[0] || (state == FIX && timestamp != null && !fixAgeUnknown &&
            timestamp < fixTimestamp)) {
            return false;
        }
        var degrees = (info.position as Position.Location).toDegrees();
        latE5 = NearbyStopMaths.toE5(degrees[0] as Double);
        lonE5 = NearbyStopMaths.toE5(degrees[1] as Double);
        fixTimestamp = timestamp == null ? 0 : timestamp as Number;
        fixAgeUnknown = timestamp == null;
        stale = decision[1];
        state = FIX;
        logFix(fixAgeUnknown ? -1 : Time.now().value() - fixTimestamp, stale);
        return true;
    }

    function onLocation(info as Position.Info) as Void {
        if (acquiring) {
            try {
                if (accept(info)) {
                    if (stale || info.accuracy < Position.QUALITY_POOR) {
                        notify();
                    } else {
                        finish(true);
                    }
                }
            } catch (e) {
                failureReason = NearbyUnavailableReason.LOCATION_ERROR;
                finish(false);
            }
        }
    }

    function onTimeout() as Void {
        if (acquiring) {
            finish(false);
        }
    }

    private function finish(hasFix as Boolean) as Void {
        timeout.stop();
        disableEvents();
        acquiring = false;
        if (!hasFix && state != FIX) {
            state = NO_FIX;
        }
        if (hasFix || state == NO_FIX) {
            notify();
        }
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

    (:debug)
    private function logFix(age as Number, isOld as Boolean) as Void {
        System.println("Nearby position: age=" + age + ", stale=" + isOld);
    }

    (:release)
    private function logFix(age as Number, isOld as Boolean) as Void {}
}

(:noNearby)
class NearbyLocation {
    function start(callback as Method) as Void {}
    function stop() as Void {}
    function refresh() as Void {}
}
