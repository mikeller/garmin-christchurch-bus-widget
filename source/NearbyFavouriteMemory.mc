import Toybox.Lang;

(:nearby, :glance)
class NearbyFavouriteMemory {
    static const RESTORED = 0;
    static const EXPIRED = 1;
    static const NO_RECORD = 2;
    static const INVALID = 3;
    static const OUT_OF_RANGE = 4;
    static const DISABLED = 5;

    (:debug)
    static function restoreReason(value as Object?, favourites as Array<Dictionary>,
                                  setting as Number, now as Number) as Number {
        if (value == null) {
            return NO_RECORD;
        }
        if (setting == 0) {
            return DISABLED;
        }
        if (!(value instanceof Dictionary)) {
            return INVALID;
        }
        var record = value as Dictionary;
        if (record["resetTime"] != null && !(record["resetTime"] instanceof Number)) {
            return INVALID;
        }
        if (record["resetTime"] instanceof Number &&
            (record["resetTime"] as Number) <= now) {
            return EXPIRED;
        }
        if (restore(record, favourites, setting, now) != null) {
            return RESTORED;
        }
        var index = record["stopIndex"];
        if (record["stopId"] instanceof Number &&
            (record["stopId"] as Number) >= 1000 &&
            (record["stopId"] as Number) <= 99999) {
            return OUT_OF_RANGE;
        }
        if (record["stopId"] == null &&
            (index instanceof Number || index instanceof Long)) {
            return OUT_OF_RANGE;
        }
        return INVALID;
    }

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
