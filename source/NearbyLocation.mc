import Toybox.Lang;
import Toybox.Position;
import Toybox.Time;
import Toybox.Timer;
import Toybox.System;

// Widget-only acquisition; no location request is made from the glance.
(:nearby)
class NearbyLocation {
    static const ACQUISITION_TIMEOUT_MS = 60000;
    static const REACQUIRE_DELAY_MS = 30000;
    static const IDLE = 0;
    static const LOCATING = 1;
    static const FIX = 2;
    static const NO_FIX = 3;

    private var state as Number = IDLE;
    private var latE5 as Number?;
    private var lonE5 as Number?;
    private var fixTimestamp as Number = 0;
    private var fixAgeUnknown as Boolean = false;
    private var fixQuality as Number = Position.QUALITY_NOT_AVAILABLE;
    private var stale as Boolean = false;
    private var acquiring as Boolean = false;
    private var firstCallback as Boolean = true;
    private var reacquirePending as Boolean = false;
    private var acquisitionState as Number = NearbyAcquisitionState.IDLE;
    private var timeout as Timer.Timer = new Timer.Timer();
    private var callback as Method?;
    private var failureReason as Number = NearbyUnavailableReason.NO_FIX;

    function start(callback as Method) as Void {
        stop();
        self.callback = callback;
        firstCallback = true;
        if (!ChristchurchBusAppProperties.nearbyEnabled()) {
            return;
        }
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
            NearbyStoredFix.saveNewer(device as Dictionary, now);
        }
        if (chosen == null) {
            state = LOCATING;
        }
        // A widget may close before a delayed acquisition starts. Listen
        // immediately even when getInfo supplied a seemingly recent fix.
        beginAcquisition();
    }

    private function beginAcquisition() as Void {
        if (callback == null) {
            return;
        }
        reacquirePending = false;
        acquiring = true;
        acquisitionState = NearbyAcquisitionState.shown();
        try {
            timeout.start(method(:onTimeout), ACQUISITION_TIMEOUT_MS, false);
            Position.enableLocationEvents(Position.LOCATION_ONE_SHOT, method(:onLocation));
        } catch (e) {
            failureReason = NearbyUnavailableReason.LOCATION_ERROR;
            finish(false);
        }
    }

    private function scheduleReacquisition() as Void {
        if (callback != null && state != IDLE) {
            reacquirePending = true;
            timeout.start(method(:onTimeout), REACQUIRE_DELAY_MS, false);
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
            "unknown" => when == null,
            "quality" => info.accuracy} as Dictionary;
        return NearbyStoredFix.valid(candidate, now) ? candidate : null;
    }

    private function applyFix(fix as Dictionary, now as Number) as Void {
        latE5 = fix["lat"] as Number;
        lonE5 = fix["lon"] as Number;
        fixTimestamp = fix["at"] as Number;
        fixAgeUnknown = fix["unknown"] == true;
        fixQuality = fix["quality"] instanceof Number ?
            fix["quality"] as Number : Position.QUALITY_LAST_KNOWN;
        stale = staleAt(now);
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
        if (firstCallback) {
            firstCallback = false;
            NearbyStoredFix.saveNewer(fix as Dictionary, now);
        } else {
            NearbyStoredFix.save(fix as Dictionary, now);
        }
        return true;
    }

    function stop() as Void {
        if (callback != null) {
            // A new last-known position may be available just before exit,
            // even if no callback was delivered in this short session.
            try {
                var now = Time.now().value();
                var finalFix = fromInfo(Position.getInfo(), now);
                if (finalFix != null) {
                    NearbyStoredFix.saveNewer(finalFix as Dictionary, now);
                }
            } catch (e) {
                // A denied or unavailable fix must not delay widget exit.
            }
        }
        timeout.stop();
        if (acquiring) {
            disableEvents();
        }
        acquiring = false;
        reacquirePending = false;
        acquisitionState = NearbyAcquisitionState.afterHide(acquisitionState);
        state = IDLE;
        callback = null;
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
        return state == FIX && staleAt(Time.now().value());
    }

    private function staleAt(now as Number) as Boolean {
        return fixAgeUnknown || fixQuality <= Position.QUALITY_LAST_KNOWN ||
            now - fixTimestamp > NearbyLocationPolicy.NEARBY_STALE_FIX_SEC;
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
                    acquisitionState = NearbyAcquisitionState.received(acquisitionState);
                    // A one-shot position has been delivered. Do not keep
                    // GPS enabled, even when its timestamp is old.
                    finish(true);
                } else {
                    // One-shot callbacks may also deliver an older or
                    // unusable position. Never replace the newer fix.
                    finish(false);
                }
            } catch (e) {
                failureReason = NearbyUnavailableReason.LOCATION_ERROR;
                finish(false);
            }
        }
    }

    function onTimeout() as Void {
        if (reacquirePending) {
            beginAcquisition();
            return;
        }
        if (acquiring) {
            acquisitionState = NearbyAcquisitionState.timedOut(acquisitionState);
            // LOCATION_ONE_SHOT remains registered until it is explicitly
            // disabled. Do not leave it active after this bounded attempt:
            // an outstanding Position listener can keep a widget alive past
            // the platform-managed timeout.
            failureReason = NearbyUnavailableReason.NO_FIX;
            finish(false);
        }
    }

    private function finish(hasFix as Boolean) as Void {
        timeout.stop();
        disableEvents();
        acquiring = false;
        acquisitionState = hasFix ? NearbyAcquisitionState.received(acquisitionState) :
            NearbyAcquisitionState.afterHide(acquisitionState);
        if (!hasFix && state != FIX) {
            state = NO_FIX;
        }
        if (hasFix || state == NO_FIX) {
            notify();
        }
        // The one-shot listener has completed; try again while visible.
        scheduleReacquisition();
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
