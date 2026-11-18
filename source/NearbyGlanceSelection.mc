import Toybox.Lang;

(:glance, :nearby)
class NearbyGlanceSelection {
    // Use the same restored favourite ID as widget startup.
    static function favourite(favourites as Array<Dictionary>, id as Number?) as Dictionary? {
        if (id != null) {
            for (var i = 0; i < favourites.size(); i++) {
                if (favourites[i]["stopId"] == id) {
                    return favourites[i];
                }
            }
        }
        return null;
    }

    // Storage lookup happens outside this pure decision. A cached nearby row
    // is used only if there are no favourites.
    (:nearby)
    static function select(favourites as Array<Dictionary>, lastId as Number?,
                           firstCached as Dictionary?) as Dictionary? {
        var selected = favourite(favourites, lastId);
        if (selected != null) {
            return selected;
        }
        return favourites.size() > 0 ? favourites[0] : firstCached;
    }
}
