import Toybox.Lang;

// Shared by departures and tiles, so together they use at most three HTTP slots.
(:glance)
class NearbyRequestSlots {
    private static var active as Number = 0;

    static function acquire() as Boolean {
        if (active >= Constants.MAX_CONCURRENT_REQUESTS) {
            return false;
        }
        active++;
        return true;
    }

    static function release() as Void {
        active--;
    }
}
