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

        var compressedData = {
            "ValidUntil" => expiresString
        };

        var visits = data["MonitoredStopVisit"] as Array<Dictionary>?;
        if (visits != null) {
            var index = 0;
            var compressedVisits = [];
            while (index < visits.size()) {
                var visit = visits[index];
                var journey = visit["MonitoredVehicleJourney"] as Dictionary<String, String or Number or Boolean or Dictionary>;
                var call = (journey["MonitoredCall"] as Dictionary<String, String or Number or Boolean or Dictionary>);
                var expectedDepartureTimeString = call["ExpectedDepartureTime"] as String;

                var compressedVisit = {
                    "ExpectedDepartureTime" => expectedDepartureTimeString,
                    "VehicleAtStop" => call["VehicleAtStop"],
                    "PublishedLineName" => journey["PublishedLineName"],
                    "DestinationName" => journey["DestinationName"],
                };

                compressedVisits.add(compressedVisit);

                index++;
            }

            compressedData["MonitoredStopVisit"] = compressedVisits;
        }

        compressedData["ErrorCondition"] = data["ErrorCondition"];

        Storage.setValue(stopId, compressedData as Dictionary<PropertyKeyType, PropertyValueType>);
    }

    static function setLastStop(stopIndex as Number) as Void {
        var stopResetTimeMin = ChristchurchBusAppProperties.getStopResetTimeMin();
        if (stopResetTimeMin > 0 && stopIndex != 0) {
            var resetTime = Time.now().add(new Time.Duration(stopResetTimeMin * 60));
            var lastStopValue = {
                :stopIndex => stopIndex,
                :resetTime => resetTime.value()
            };
            Storage.setValue(Constants.LAST_STOP_INDEX_NAME, lastStopValue as PropertyValueType);

            Utils.log("Updating last stop index: " + stopIndex + ", expires " + Utils.dateToIsoString(resetTime));
        } else {
            Storage.deleteValue(Constants.LAST_STOP_INDEX_NAME);

            Utils.log("Reset last stop index.");

        }
    }

    static function getLastStop() as Number {
        var lastStopValue = Storage.getValue(Constants.LAST_STOP_INDEX_NAME) as Dictionary<Symbol, Number>?;
        if (lastStopValue != null) {
            var resetTimeValue = lastStopValue[:resetTime] as Number;
            var resetTime = null;
            if (resetTimeValue != -1) {
                resetTime = new Time.Moment(resetTimeValue);
            }

            if (resetTime == null || !resetTime.lessThan(Time.now())) {
                var stopIndex = lastStopValue[:stopIndex] as Number;

                Utils.log("Got last stop index: " + stopIndex + ", expires " + (resetTime == null ? "never" : Utils.dateToIsoString(resetTime)));

                return stopIndex;
            } else {
                Utils.log("Last stop index expired at " + Utils.dateToIsoString(resetTime));
            }
        }

        return 0;
    }
}
