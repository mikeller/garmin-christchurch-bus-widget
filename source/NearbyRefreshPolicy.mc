import Toybox.Lang;

(:nearby)
class NearbyRefreshPolicy {
    static const MIN_SECONDS = 30;
    static const MIN_METRES = 50;
    static const MOVING_METRES = 5;
    static const MOVING_SECONDS = 60;

    static function shouldUpdateDistances(lat as Number, lon as Number,
                                          fixAt as Number, dataLat as Number?,
                                          dataLon as Number?, dataAt as Number,
                                          pending as Boolean) as Boolean {
        return pending || dataLat == null || dataLon == null ||
            lat != dataLat || lon != dataLon || fixAt != dataAt;
    }

    static function shouldRefresh(lat as Number, lon as Number,
                                  previousLat as Number?, previousLon as Number?,
                                  lastRequest as Number, now as Number) as Boolean {
        if (previousLat == null || previousLon == null) {
            return true;
        }
        if (lastRequest >= 0 && (now < lastRequest ||
            now - lastRequest < MIN_SECONDS)) {
            return false;
        }
        var metres = NearbyStopMaths.approxMetres(lat, lon,
            previousLat as Number, previousLon as Number);
        return metres > MIN_METRES ||
            (metres > MOVING_METRES && (lastRequest < 0 ||
                now - lastRequest >= MOVING_SECONDS));
    }
}
