import Toybox.Lang;

(:nearby)
class NearbyFixDecision {
    static function staleForData(dataAt as Number, wasStale as Boolean,
                                 pending as Boolean, now as Number) as Boolean {
        return pending || wasStale || dataAt == 0 ||
            now - dataAt > NearbyLocationPolicy.NEARBY_STALE_FIX_SEC;
    }

    static function show(favourite as Boolean, hasDistance as Boolean,
                         stale as Boolean) as Boolean {
        return stale && (!favourite || hasDistance);
    }
}
