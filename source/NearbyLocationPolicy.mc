import Toybox.Lang;
import Toybox.Position;

(:nearby)
class NearbyLocationPolicy {
    static const NEARBY_STALE_FIX_SEC = 600;

    // [usable, stale, acquire]. A missing timestamp is unknown age, not an
    // absent location. No arbitrary upper age limit is imposed.
    static function decide(accuracy as Position.Quality, fixSeconds as Number?,
                           nowSeconds as Number) as Array<Boolean> {
        if (accuracy < Position.QUALITY_LAST_KNOWN) {
            return [false, false, true];
        }
        var stale = fixSeconds == null ||
            nowSeconds - (fixSeconds as Number) > NEARBY_STALE_FIX_SEC;
        return [true, stale, stale || accuracy < Position.QUALITY_POOR];
    }
}
