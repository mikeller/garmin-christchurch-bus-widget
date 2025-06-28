import Toybox.Lang;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:glance)
class ChristchurchBusDataCache {
    static function tryGetCachedData(stopId as Number, ignoreExpiry as Boolean) as Dictionary<String, String or Array>? {
        var data = Storage.getValue(stopId) as Dictionary<String, String or Array>?;
        if (data != null) {
            var expiresString = data["ValidUntil"] as String?;
            var expires = Utils.parseIsoDate(expiresString);
            var isStale = expires == null || (expires as Moment).lessThan(Time.now());
            if (!isStale || ignoreExpiry) {
                Utils.log("Cache hit (" + (isStale ? "stale, " : "") + "expiry: " + expiresString + "): " + stopId);

                return data;
            } else {
                Utils.log("Cache miss (stale data found, expiry: " + expiresString + "): " + stopId);

                return null;
            }
        }

        Utils.log("Cache miss" + (ignoreExpiry ? " (ignoring expiry)" : "") + ": " + stopId);

        return null;
    }

    static function setCachedData(stopId as Number, data as Dictionary<String, String or Array>) as Void {
        var expiresString = data["ValidUntil"] as String?;
        Utils.log("Cache update (expiry: " + expiresString + "): " + stopId);

        Storage.setValue(stopId, data as Dictionary<PropertyKeyType, PropertyValueType>);
    }
}
