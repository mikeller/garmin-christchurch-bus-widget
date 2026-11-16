import Toybox.Lang;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Time;

(:nearby)
class NearbyStoredFix {
    static const KEY = "nearby:fix";
    static const VERSION = 1;

    static function valid(value as Object?, now as Number) as Boolean {
        if (!(value instanceof Dictionary)) {
            return false;
        }
        var fix = value as Dictionary;
        if (!(fix["v"] instanceof Number) || fix["v"] != VERSION ||
            !(fix["lat"] instanceof Number) || !(fix["lon"] instanceof Number) ||
            !(fix["at"] instanceof Number)) {
            return false;
        }
        var lat = fix["lat"] as Number;
        var lon = fix["lon"] as Number;
        var at = fix["at"] as Number;
        var savedAt = fix["savedAt"];
        var unknown = fix["unknown"];
        return lat >= -9000000 && lat <= 9000000 &&
            lon >= -18000000 && lon <= 18000000 &&
            at >= 0 && at <= now + 86400 &&
            (savedAt == null || (savedAt instanceof Number && savedAt >= 0 &&
                savedAt <= now + 86400)) &&
            (unknown == null || unknown instanceof Boolean);
    }

    static function choose(fromDevice as Dictionary?, stored as Dictionary?,
                           now as Number) as Dictionary? {
        var deviceValid = valid(fromDevice, now);
        var storedValid = valid(stored, now);
        if (!deviceValid) {
            return storedValid ? stored : null;
        }
        if (!storedValid || (fromDevice as Dictionary)["at"] >= (stored as Dictionary)["at"]) {
            return fromDevice;
        }
        return stored;
    }

    static function shouldWrite(previous as Dictionary?, candidate as Dictionary,
                                now as Number) as Boolean {
        if (!valid(candidate, now)) {
            return false;
        }
        if (!valid(previous, now)) {
            return true;
        }
        var old = previous as Dictionary;
        var lastWrite = old["savedAt"] instanceof Number ?
            old["savedAt"] as Number : old["at"] as Number;
        if (now < lastWrite || now - lastWrite < 60) {
            return false;
        }
        if ((candidate["at"] as Number) <= (old["at"] as Number)) {
            return false;
        }
        var moved = NearbyStopMaths.movedMoreThan(candidate["lat"] as Number,
            candidate["lon"] as Number, old["lat"] as Number, old["lon"] as Number, 100);
        return moved || now - (old["at"] as Number) > 600;
    }

    static function read(now as Number) as Dictionary? {
        try {
            var stored = Storage.getValue(KEY);
            return valid(stored, now) ? stored as Dictionary : null;
        } catch (e) {
            return null;
        }
    }

    static function save(candidate as Dictionary, now as Number) as Void {
        try {
            if (shouldWrite(read(now), candidate, now)) {
                candidate["savedAt"] = now;
                Storage.setValue(KEY, candidate as PropertyValueType);
            }
        } catch (e) {
            // A full object store must not prevent live location updates.
        }
    }
}
