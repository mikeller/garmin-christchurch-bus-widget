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
        var now = Time.now().value();
        var device = null as Dictionary?;
        var info = null as Position.Info?;
        try {
            info = Position.getInfo();
            device = fromInfo(info, now);
        } catch (e) {
            failureReason = NearbyUnavailableReason.LOCATION_ERROR;
        }
        var chosen = NearbyStoredFix.choose(device, NearbyStoredFix.read(now), now);
        if (chosen != null) {
            applyFix(chosen as Dictionary, now);
            notify();
        }
        if (device != null && info != null && info.accuracy >= Position.QUALITY_POOR) {
            NearbyStoredFix.save(device as Dictionary, now);
        }
        if (chosen == null || stale || info == null ||
            info.accuracy < Position.QUALITY_POOR) {
            if (chosen == null) {
                state = LOCATING;
            }
            acquiring = true;
            try {
                timeout.start(method(:onTimeout), ACQUISITION_TIMEOUT_MS, false);
                Position.enableLocationEvents(Position.LOCATION_ONE_SHOT, method(:onLocation));
            } catch (e) {
                failureReason = NearbyUnavailableReason.LOCATION_ERROR;
                finish(false);
            }
        }
    }

    private function fromInfo(info as Position.Info?, now as Number) as Dictionary? {
        if (info == null || info.position == null ||
            info.accuracy < Position.QUALITY_LAST_KNOWN) {
            return null;
        }
        var when = null as Number?;
        try {
            if (info.when != null) {
                when = (info.when as Time.Moment).value();
            }
        } catch (e) {
            // A missing or unreadable age still permits use of the position.
        }
        var degrees = (info.position as Position.Location).toDegrees();
        if ((degrees[0] as Double) < -90.0d || (degrees[0] as Double) > 90.0d ||
            (degrees[1] as Double) < -180.0d || (degrees[1] as Double) > 180.0d) {
            return null;
        }
        var candidate = {"v" => NearbyStoredFix.VERSION,
            "lat" => NearbyStopMaths.toE5(degrees[0] as Double),
            "lon" => NearbyStopMaths.toE5(degrees[1] as Double),
            "at" => when == null ? now : when as Number,
            "unknown" => when == null} as Dictionary;
        return NearbyStoredFix.valid(candidate, now) ? candidate : null;
    }

    private function applyFix(fix as Dictionary, now as Number) as Void {
        latE5 = fix["lat"] as Number;
        lonE5 = fix["lon"] as Number;
        fixTimestamp = fix["at"] as Number;
        fixAgeUnknown = fix["unknown"] == true;
        stale = fixAgeUnknown || now - fixTimestamp > NearbyLocationPolicy.NEARBY_STALE_FIX_SEC;
        state = FIX;
        logFix(fixAgeUnknown ? -1 : now - fixTimestamp, stale);
    }

    private function accept(info as Position.Info?) as Boolean {
        var now = Time.now().value();
        var fix = fromInfo(info, now);
        if (fix == null || (state == FIX && (fix as Dictionary)["at"] < fixTimestamp)) {
            return false;
        }
        applyFix(fix as Dictionary, now);
        NearbyStoredFix.save(fix as Dictionary, now);
        return true;
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
