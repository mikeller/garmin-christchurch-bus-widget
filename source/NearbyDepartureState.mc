import Toybox.Lang;

(:nearby)
class NearbyDepartureState {
    // A stale cache is not a connection failure until the update actually
    // fails or has been outstanding long enough to be considered timed out.
    static function failed(wasFailed as Boolean, completed as Boolean,
                           stale as Boolean, timedOut as Boolean) as Boolean {
        if (completed) {
            return stale;
        }
        return wasFailed || timedOut;
    }
}
