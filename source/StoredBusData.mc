import Toybox.Lang;

// Values in Properties and Storage survive application upgrades. Never cast
// an unvalidated persisted object straight into a page or departure view.
(:glance)
class StoredBusData {
    // A value written as a Number (e.g. Time.Moment.value()) can come back
    // from Storage.getValue() typed as Long instead, even well within
    // 32-bit range; this was observed for "resetTime" via a real
    // Storage.setValue()/getValue() round trip in the SDK 9.3.0 simulator
    // (descentmk1), not yet confirmed on physical hardware. Treat both as
    // the same persisted integer rather than rejecting an otherwise-valid
    // record as malformed.
    static function isStoredInteger(value as Object?) as Boolean {
        return value instanceof Number || value instanceof Long;
    }

    static function toStoredNumber(value as Object) as Number {
        return value instanceof Long ? (value as Long).toNumber() : value as Number;
    }

    static function validStop(value as Object?) as Boolean {
        if (!(value instanceof Dictionary)) {
            return false;
        }
        var stop = value as Dictionary;
        return stop["stopId"] instanceof Number &&
            (stop["stopId"] as Number) >= 1000 && (stop["stopId"] as Number) <= 99999 &&
            stop["displayName"] instanceof String;
    }

    static function validLastStop(value as Object?, favourites as Array<Dictionary>) as Boolean {
        if (!(value instanceof Dictionary)) {
            return false;
        }
        var entry = value as Dictionary;
        if (entry["resetTime"] != null && !isStoredInteger(entry["resetTime"])) {
            return false;
        }
        if (entry["stopId"] != null) {
            return entry["stopId"] instanceof Number &&
                (entry["stopId"] as Number) >= 1000 && (entry["stopId"] as Number) <= 99999;
        }
        return entry["stopIndex"] instanceof Number &&
            (entry["stopIndex"] as Number) >= 0 &&
            (entry["stopIndex"] as Number) < favourites.size();
    }

    static function validDeparture(value as Object?) as Boolean {
        if (!(value instanceof Dictionary)) {
            return false;
        }
        var data = value as Dictionary;
        if (!(data["ValidUntil"] instanceof String)) {
            return false;
        }
        var visits = data["MonitoredStopVisit"];
        if (visits instanceof Array) {
            for (var i = 0; i < (visits as Array).size(); i++) {
                var visit = (visits as Array)[i];
                if (!(visit instanceof Dictionary)) {
                    return false;
                }
                var row = visit as Dictionary;
                if (!(row["ExpectedDepartureTime"] instanceof String) ||
                    !(row["VehicleAtStop"] instanceof Boolean) ||
                    !(row["PublishedLineName"] instanceof String) ||
                    !(row["DestinationName"] instanceof String)) {
                    return false;
                }
            }
            return true;
        }
        var error = data["ErrorCondition"];
        if (error instanceof Dictionary) {
            var keys = (error as Dictionary).keys();
            for (var i = 0; i < keys.size(); i++) {
                var detail = (error as Dictionary)[keys[i]];
                if ("Description".equals(keys[i])) {
                    if (!(detail instanceof String)) {
                        return false;
                    }
                } else if (!(detail instanceof Dictionary) ||
                    !((detail as Dictionary)["ErrorText"] instanceof String)) {
                    return false;
                }
            }
            return true;
        }
        return false;
    }

    (:nearby)
    static function validNearbyResult(value as Object?) as Boolean {
        if (!(value instanceof Dictionary)) {
            return false;
        }
        var result = value as Dictionary;
        if (!(result["at"] instanceof Number) || !(result["stops"] instanceof Array)) {
            return false;
        }
        var rows = result["stops"] as Array;
        for (var i = 0; i < rows.size(); i++) {
            if (!(rows[i] instanceof Array) || (rows[i] as Array).size() != 3) {
                return false;
            }
            var row = rows[i] as Array;
            if (!(row[0] instanceof Number) || (row[0] as Number) < 1000 ||
                (row[0] as Number) > 99999 || !(row[1] instanceof String) ||
                !(row[2] instanceof Number) || (row[2] as Number) < 0) {
                return false;
            }
        }
        return true;
    }
}
