import Toybox.Lang;
import Toybox.Position;

(:nearby)
class NearbyLocationPolicy {
    static const RECENT_MAX_AGE_SEC = 300;
    static const NEARBY_LAST_KNOWN_MAX_AGE_SEC = 1800;

    static function accepts(accuracy as Position.Quality, fixSeconds as Number?,
                            nowSeconds as Number) as Boolean {
        if (fixSeconds == null || accuracy < Position.QUALITY_LAST_KNOWN) {
            return false;
        }
        var age = nowSeconds - (fixSeconds as Number);
        if (age < 0) {
            return false;
        }
        if (accuracy == Position.QUALITY_LAST_KNOWN) {
            // A recent fix suffices indoors when the user has not travelled;
            // 30 minutes bounds the risk of showing stops from an earlier trip.
            return age <= NEARBY_LAST_KNOWN_MAX_AGE_SEC;
        }
        return accuracy >= Position.QUALITY_POOR && age <= RECENT_MAX_AGE_SEC;
    }
}
