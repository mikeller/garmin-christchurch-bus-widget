import Toybox.Lang;

// A departure is shared only when both the published line and destination
// match exactly. Unknown, empty and error responses do not establish coverage.
(:nearby)
class NearbyDepartureCoverage {
    static function keys(data as Dictionary?) as Array? {
        if (data == null || data["ErrorCondition"] != null) {
            return null;
        }
        var visits = data["MonitoredStopVisit"];
        if (!(visits instanceof Array) || (visits as Array).size() == 0) {
            return null;
        }
        var result = [] as Array;
        for (var i = 0; i < (visits as Array).size(); i++) {
            var visit = (visits as Array)[i];
            if (!(visit instanceof Dictionary)) {
                return null;
            }
            var line = (visit as Dictionary)["PublishedLineName"];
            var destination = (visit as Dictionary)["DestinationName"];
            if (!(line instanceof String) || !(destination instanceof String) ||
                (line as String).length() == 0 || (destination as String).length() == 0) {
                return null;
            }
            var key = [line, destination];
            if (!contains(result, key)) {
                result.add(key);
            }
        }
        return result;
    }

    static function contains(keys as Array, key as Array) as Boolean {
        for (var i = 0; i < keys.size(); i++) {
            var existing = keys[i] as Array;
            if ((existing[0] as String).equals(key[0] as String) &&
                (existing[1] as String).equals(key[1] as String)) {
                return true;
            }
        }
        return false;
    }

    // entries: [stop code, distance squared, compressed departure data or null].
    // Favourites are only providers if strictly closer than the candidate.
    // The first n+3 non-favourites (at most eight) are considered. Incomplete
    // data stays visible and cannot hide another stop.
    static function select(entries as Array, favourites as Array, n as Number) as Array {
        var limit = n + 3;
        if (limit > 8) {
            limit = 8;
        }
        var selected = [] as Array;
        var covered = [] as Array;
        var considered = 0;
        for (var i = 0; i < entries.size() && considered < limit && selected.size() < n; i++) {
            var entry = entries[i] as Array;
            var isFavourite = entry[3] == true;
            if (isFavourite) {
                continue;
            }
            considered++;
            var candidateKeys = keys(entry[2] as Dictionary?);
            var allCovered = candidateKeys != null;
            if (candidateKeys != null) {
                for (var f = 0; f < favourites.size(); f++) {
                    var favourite = favourites[f] as Array;
                    if ((favourite[1] as Long) < (entry[1] as Long)) {
                        var provider = keysFor(favourite);
                        if (provider != null) {
                            add(covered, provider as Array);
                        }
                    }
                }
                for (var k = 0; k < (candidateKeys as Array).size(); k++) {
                    if (!contains(covered, (candidateKeys as Array)[k] as Array)) {
                        allCovered = false;
                        break;
                    }
                }
            }
            if (!allCovered) {
                selected.add(entry);
                if (candidateKeys != null) {
                    add(covered, candidateKeys as Array);
                }
            }
        }
        return selected;
    }

    private static function keysFor(entry as Array) as Array? {
        return keys(entry[2] as Dictionary?);
    }

    private static function add(covered as Array, keys as Array) as Void {
        for (var i = 0; i < keys.size(); i++) {
            var key = keys[i] as Array;
            if (!contains(covered, key)) {
                covered.add(key);
            }
        }
    }
}
