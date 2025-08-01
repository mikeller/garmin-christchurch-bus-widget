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

    static function setLastStop(stopIndex as Number) as Void {
        if (stopIndex != 0) {
            var stopResetTimeMin = ChristchurchBusAppProperties.getStopResetTimeMin();
            if (stopResetTimeMin > 0) {
                var resetTime = Time.now().add(new Time.Duration(stopResetTimeMin * 60));
                var lastStopValue = {
                    "stopIndex" => stopIndex,
                    "resetTime" => resetTime.value(),
                };
                Storage.setValue(Constants.LAST_STOP_INDEX_NAME, lastStopValue as PropertyValueType);

                Utils.log("Updating last stop index: " + stopIndex + ", expires " + Utils.dateToIsoString(resetTime));

                return;
            } else if (stopResetTimeMin == -1) {
                var lastStopValue = {
                    "stopIndex" => stopIndex,
                };
                Storage.setValue(Constants.LAST_STOP_INDEX_NAME, lastStopValue as PropertyValueType);

                Utils.log("Updating last stop index: " + stopIndex + ", never expires");

                return;
            }
        }

        Storage.deleteValue(Constants.LAST_STOP_INDEX_NAME);

        Utils.log("Reset last stop index.");
    }

    static function getLastStop() as Number {
        var lastStopValue = Storage.getValue(Constants.LAST_STOP_INDEX_NAME) as Dictionary<String, Number>?;
        if (lastStopValue != null) {
            var resetTimeValue = lastStopValue["resetTime"] as Number?;
            var resetTime = null;
            if (resetTimeValue != null) {
                resetTime = new Time.Moment(resetTimeValue);
            }

            if (resetTime == null || !resetTime.lessThan(Time.now())) {
                var stopIndex = lastStopValue["stopIndex"] as Number?;
                if (stopIndex == null) {
                    stopIndex = 0;
                }

                Utils.log("Got last stop index: " + stopIndex + ", expires " + (resetTime == null ? "never" : Utils.dateToIsoString(resetTime)));

                return stopIndex;
            } else {
                Utils.log("Last stop index expired at " + Utils.dateToIsoString(resetTime));
            }
        }

        return 0;
    }
}
