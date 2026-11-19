import Toybox.Lang;

(:nearby)
class NearbyRecheckPolicy {
    static const STALE_SECONDS = 120;

    static function eligible(enteringNearby as Boolean, enabled as Boolean,
                             inFlight as Boolean, used as Number, visible as Boolean,
                             running as Boolean, checkedAt as Number?,
                             now as Number) as Boolean {
        return enteringNearby && enabled && !inFlight && used < 8 &&
            !visible && !running && (checkedAt == null || now < checkedAt as Number ||
            now - (checkedAt as Number) > STALE_SECONDS);
    }
}
