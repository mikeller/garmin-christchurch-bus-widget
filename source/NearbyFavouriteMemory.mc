import Toybox.Lang;

(:nearby)
class NearbyFavouriteMemory {
    static function selectedFavourite(page as Dictionary, favourites as Array<Dictionary>) as Number? {
        var id = page["stopId"] as Number?;
        if (page["nearby"] == true || id == null) {
            return null;
        }
        for (var i = 0; i < favourites.size(); i++) {
            if (favourites[i]["stopId"] == id) {
                return id;
            }
        }
        return null;
    }

    // Old records contain stopIndex; newer records contain stopId. An unknown
    // ID is not a favourite, even if it looks like a valid stop code.
    static function restore(record as Dictionary?, favourites as Array<Dictionary>,
                            setting as Number, now as Number) as Number? {
        if (record == null || setting == 0) {
            return null;
        }
        var legacyLong = record["stopId"] == null &&
            record["stopIndex"] instanceof Long &&
            (record["stopIndex"] as Long) >= 0l &&
            (record["stopIndex"] as Long) < favourites.size().toLong() &&
            (record["resetTime"] == null || record["resetTime"] instanceof Number);
        if (!legacyLong && !StoredBusData.validLastStop(record, favourites)) {
            return null;
        }
        var expires = record["resetTime"] as Number?;
        if (expires != null && (expires as Number) <= now) {
            return null;
        }
        var id = record["stopId"] as Number?;
        if (id == null) {
            var index = legacyLong ? (record["stopIndex"] as Long).toNumber() :
                record["stopIndex"] as Number;
            id = favourites[index]["stopId"] as Number;
        }
        for (var i = 0; i < favourites.size(); i++) {
            if (favourites[i]["stopId"] == id) {
                return id;
            }
        }
        return null;
    }
}
