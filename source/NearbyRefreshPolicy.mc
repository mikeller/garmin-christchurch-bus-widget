import Toybox.Lang;

(:nearby)
class NearbyRefreshPolicy {
    static const MIN_SECONDS = 30;
    static const MIN_METRES = 100;

    static function shouldRefresh(lat as Number, lon as Number,
                                  previousLat as Number?, previousLon as Number?,
                                  lastRequest as Number, now as Number) as Boolean {
        if (previousLat == null || previousLon == null) {
            return true;
        }
        return (lastRequest < 0 || (now >= lastRequest &&
            now - lastRequest >= MIN_SECONDS)) &&
            NearbyStopMaths.movedMoreThan(lat, lon, previousLat as Number,
                previousLon as Number, MIN_METRES);
    }
}
