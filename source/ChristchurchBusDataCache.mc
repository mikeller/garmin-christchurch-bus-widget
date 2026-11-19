import Toybox.Lang;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:glance)
class ChristchurchBusDataCache {
    static function tryGetCachedData(stopId as Number, ignoreExpiry as Boolean) as Dictionary<String, String or Array>? {
        var stored = Storage.getValue(stopId);
        if (stored != null && !StoredBusData.validDeparture(stored)) {
            Storage.deleteValue(stopId);
            return null;
        }
        var data = stored as Dictionary<String, String or Array>?;
        if (data != null) {
            var expiresString = data["ValidUntil"] as String?;
            var expires = null;
            try {
                expires = Utils.parseIsoDate(expiresString);
            } catch (e) {
                Storage.deleteValue(stopId);
                return null;
            }
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

    static function setLastStop(stopId as Number, firstStopId as Number) as Void {
        if (stopId != firstStopId) {
            var stopResetTimeMin = ChristchurchBusAppProperties.getStopResetTimeMin();
            if (stopResetTimeMin > 0) {
                var resetTime = Time.now().add(new Time.Duration(stopResetTimeMin * 60));
                var lastStopValue = {
                    "stopId" => stopId,
                    "resetTime" => resetTime.value(),
                };
                Storage.setValue(Constants.LAST_STOP_INDEX_NAME, lastStopValue as PropertyValueType);

                Utils.log("Updating last stop: " + stopId + ", expires " + Utils.dateToIsoString(resetTime));

                return;
            } else if (stopResetTimeMin == -1) {
                var lastStopValue = {
                    "stopId" => stopId,
                };
                Storage.setValue(Constants.LAST_STOP_INDEX_NAME, lastStopValue as PropertyValueType);

                Utils.log("Updating last stop: " + stopId + ", never expires");

                return;
            }
        }

        Storage.deleteValue(Constants.LAST_STOP_INDEX_NAME);

        Utils.log("Reset last stop index.");
    }

    (:nearby)
    static function clearLastStop() as Void {
        Storage.deleteValue(Constants.LAST_STOP_INDEX_NAME);
        NearbyLastStopTrace.cleared();
    }

    (:nearby)
    static function rememberFavouritePage(page as Dictionary,
                                          favourites as Array<Dictionary>) as Void {
        var selected = NearbyFavouriteMemory.selectedFavourite(page, favourites);
        if (selected != null) {
            setLastStop(selected as Number, favourites[0]["stopId"] as Number);
            NearbyLastStopTrace.favourite();
        }
        // A nearby-only page leaves the previous favourite (and expiry)
        // intact for both widget startup and the glance.
    }

    static function getLastStop(favourites as Array<Dictionary>) as Number? {
        var stored = Storage.getValue(Constants.LAST_STOP_INDEX_NAME);
        if (ChristchurchBusAppProperties.getStopResetTimeMin() == 0) {
            return null;
        }
        if (stored != null && !StoredBusData.validLastStop(stored, favourites)) {
            Storage.deleteValue(Constants.LAST_STOP_INDEX_NAME);
            return null;
        }
        var lastStopValue = stored as Dictionary<String, Object>?;
        if (lastStopValue != null) {
            // Storage.getValue() can return an originally-Number resetTime
            // as Long (observed in the simulator); see
            // StoredBusData.isStoredInteger().
            var storedResetTime = lastStopValue["resetTime"];
            var resetTimeValue = storedResetTime != null ?
                StoredBusData.toStoredNumber(storedResetTime) : null;
            var resetTime = null;
            if (resetTimeValue != null) {
                resetTime = new Time.Moment(resetTimeValue);
            }

            if (resetTime == null || resetTimeValue > Time.now().value()) {
                var stopId = lastStopValue["stopId"] as Number?;
                if (stopId == null) {
                    var oldIndex = lastStopValue["stopIndex"] as Number?;
                    if (oldIndex != null && oldIndex >= 0 && oldIndex < favourites.size()) {
                        stopId = favourites[oldIndex]["stopId"] as Number;
                        lastStopValue["stopId"] = stopId;
                        lastStopValue.remove("stopIndex");
                        Storage.setValue(Constants.LAST_STOP_INDEX_NAME, lastStopValue as PropertyValueType);
                    } else {
                        Storage.deleteValue(Constants.LAST_STOP_INDEX_NAME);
                    }
                }

                return stopId;
            } else {
                Utils.log("Last stop index expired at " + Utils.dateToIsoString(resetTime));
            }
        }

        return null;
    }

    (:nearby, :glance)
    static function getLastFavourite(favourites as Array<Dictionary>) as Number? {
        var stored = Storage.getValue(Constants.LAST_STOP_INDEX_NAME);
        var setting = ChristchurchBusAppProperties.getStopResetTimeMin();
        var now = Time.now().value();
        return restoreLastFavourite(stored, favourites, setting, now);
    }

    (:nearby, :glance)
    private static function restoreLastFavourite(stored as Object?,
                                                 favourites as Array<Dictionary>,
                                                 setting as Number, now as Number) as Number? {
        var record = stored instanceof Dictionary ? stored as Dictionary : null;
        var id = NearbyFavouriteMemory.restore(record, favourites, setting, now);
        if (stored != null && id == null) {
            Storage.deleteValue(Constants.LAST_STOP_INDEX_NAME);
        }
        return id;
    }

    // Keep diagnostic output on widget startup, not in the constrained glance.
    (:nearby)
    static function getLastFavouriteForWidget(favourites as Array<Dictionary>) as Number? {
        var stored = Storage.getValue(Constants.LAST_STOP_INDEX_NAME);
        var setting = ChristchurchBusAppProperties.getStopResetTimeMin();
        var now = Time.now().value();
        NearbyLastStopTrace.restore(stored, favourites, setting, now);
        return restoreLastFavourite(stored, favourites, setting, now);
    }

    (:nearby)
    static function setNearbyStops(stops as Array, fixTime as Number) as Void {
        try {
            Storage.setValue("nearby:last", {"stops" => stops, "at" => fixTime} as PropertyValueType);
        } catch (e) {
            Utils.log("Unable to persist nearby result.");
        }
    }

    (:nearby)
    static function discardInvalidNearbyResult() as Void {
        try {
            var result = Storage.getValue("nearby:last");
            if (result != null && !StoredBusData.validNearbyResult(result)) {
                Storage.deleteValue("nearby:last");
            }
        } catch (e) {
            // Failure to read stale data must not prevent nearby acquisition.
        }
    }

    // Storage returns the whole record; retain only the matching row, not the
    // tile, distances or the other nearby stops, in the glance.
    (:glance, :nearby)
    static function getNearbyStop(stopId as Number?) as Dictionary? {
        try {
            var stored = Storage.getValue("nearby:last");
            if (!StoredBusData.validNearbyResult(stored)) {
                return null;
            }
            var result = stored as Dictionary;
            var rows = result["stops"] as Array?;
            var at = result["at"] as Number?;
            // A zero timestamp means the position's age was unknown, not that
            // the widget failed to cache the nearby result.
            if (at == null || at < 0) {
                return null;
            }
            for (var i = 0; i < (rows as Array).size(); i++) {
                var row = (rows as Array)[i] as Array;
                if (stopId == null || row[0] == stopId) {
                    return {"stopId" => row[0], "displayName" => row[1], "nearbyAt" => at};
                }
            }
        } catch (e) {
            // Corrupt or missing persisted data is an ordinary glance fallback.
        }
        return null;
    }
}
