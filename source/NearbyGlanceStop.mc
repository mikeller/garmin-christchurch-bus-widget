import Toybox.Lang;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Time;

// Independent of LastStop, which remembers favourites only for widget startup.
(:nearby)
class NearbyGlanceStop {
    static const KEY = "GlanceStop";

    static function valid(value as Object?, now as Number) as Boolean {
        if (!(value instanceof Dictionary)) {
            return false;
        }
        var record = value as Dictionary;
        return record["stopId"] instanceof Number &&
            (record["stopId"] as Number) >= 1000 &&
            (record["stopId"] as Number) <= 99999 &&
            record["at"] instanceof Number &&
            (record["at"] as Number) >= 0 &&
            (record["at"] as Number) <= now + 86400;
    }

    static function shouldWrite(page as Dictionary, previous as Object?,
                                now as Number) as Boolean {
        var id = page["stopId"];
        if (!(id instanceof Number) || (id as Number) < 1000 ||
            (id as Number) > 99999) {
            return false; // Nearby status/locating slot, not a stop.
        }
        if (!valid(previous, now)) {
            return true;
        }
        var record = previous as Dictionary;
        return record["stopId"] != id || now < (record["at"] as Number) ||
            now - (record["at"] as Number) >= 60;
    }

    // The glance may use this only in its :nearby path; malformed persisted
    // values must never be cast directly to a stop or shown as a title.
    static function read() as Dictionary? {
        try {
            var stored = Storage.getValue(KEY);
            return valid(stored, Time.now().value()) ? stored as Dictionary : null;
        } catch (e) {
            return null;
        }
    }

    static function rememberPage(page as Dictionary) as Void {
        try {
            var now = Time.now().value();
            var previous = Storage.getValue(KEY);
            if (shouldWrite(page, previous, now)) {
                Storage.setValue(KEY, {"stopId" => page["stopId"], "at" => now}
                    as PropertyValueType);
            }
        } catch (e) {
            // Object-store exhaustion must not prevent the stop from loading.
        }
    }
}
