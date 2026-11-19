import Toybox.Lang;

// A departure is shared only when both the published line and destination
// match exactly. Unknown, empty and error responses do not establish coverage.
(:nearby)
class NearbyDepartureCoverage {
    static const MAX_VISITS = 32;

    static function keys(data as Dictionary?) as Array? {
        if (data == null || data["ErrorCondition"] != null) {
            return null;
        }
        var visits = data["MonitoredStopVisit"];
        if (!(visits instanceof Array) || (visits as Array).size() == 0 ||
            (visits as Array).size() > MAX_VISITS) {
            return null;
        }
        var result = [] as Array;
        var seen = {} as Dictionary<String, Boolean>;
        for (var i = 0; i < (visits as Array).size(); i++) {
            NearbyWorkCount.iteration();
            NearbyWorkCount.visit();
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
            // Length-prefix the first field so any punctuation in either
            // field remains unambiguous. Do not case-fold or truncate names.
            var key = (line as String).length().toString() + ":" + line + destination;
            if (!seen.hasKey(key)) {
                seen[key] = true;
                result.add(key);
            }
        }
        return result;
    }

    // Entry index 2 is the accumulated key array, index 6 its membership
    // dictionary. Merge only completed responses; a no-info response cannot
    // revoke an already observed provider key in this location session.
    static function mergeInto(entry as Array, fresh as Array?) as Boolean {
        if (fresh == null) {
            return false;
        }
        var changed = false;
        var accumulated = entry[2] as Array?;
        var index = entry[6] as Dictionary<String, Boolean>;
        if (accumulated == null) {
            accumulated = [] as Array;
            entry[2] = accumulated;
        }
        for (var i = 0; i < (fresh as Array).size(); i++) {
            NearbyWorkCount.iteration();
            var key = (fresh as Array)[i] as String;
            if (!index.hasKey(key)) {
                index[key] = true;
                (accumulated as Array).add(key);
                changed = true;
            }
        }
        return changed;
    }

    // entries: [stop code, distance squared, accumulated keys or null, ...].
    // Favourites are only providers if strictly closer than the candidate.
    // The first n+3 non-favourites (at most eight) are considered. Incomplete
    // data stays visible and cannot hide another stop.
    static function select(entries as Array, favourites as Array, n as Number) as Array {
        return split(entries, favourites, n)[0] as Array;
    }

    // [selected, coverageDropped]. Do not label stops beyond the page limit
    // as dropped: their departure keys were never evaluated for coverage.
    static function split(entries as Array, favourites as Array, n as Number) as Array {
        var selected = [] as Array;
        var dropped = [] as Array;
        if (n <= 0) {
            return [selected, dropped];
        }
        var limit = n + 3;
        if (limit > 8) {
            limit = 8;
        }
        var covered = {} as Dictionary<String, Boolean>;
        var considered = 0;
        var folded = {} as Dictionary<Number, Boolean>;
        for (var i = 0; i < entries.size() && considered < limit && selected.size() < n; i++) {
            NearbyWorkCount.iteration();
            var entry = entries[i] as Array;
            var isFavourite = entry[3] == true;
            if (isFavourite) {
                continue;
            }
            considered++;
            var candidateKeys = entry[2] as Array?;
            var allCovered = candidateKeys != null;
            if (candidateKeys != null) {
                for (var f = 0; f < favourites.size(); f++) {
                    NearbyWorkCount.iteration();
                    var favourite = favourites[f] as Array;
                    if ((favourite[1] as Long) < (entry[1] as Long) &&
                        folded[f] != true) {
                        var provider = favourite[2] as Array?;
                        if (provider != null) {
                            add(covered, provider as Array);
                        }
                        folded[f] = true;
                    }
                }
                for (var k = 0; k < (candidateKeys as Array).size(); k++) {
                    NearbyWorkCount.iteration();
                    if (!covered.hasKey((candidateKeys as Array)[k] as String)) {
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
            } else {
                dropped.add(entry);
            }
        }
        return [selected, dropped];
    }

    private static function add(covered as Dictionary<String, Boolean>, keys as Array) as Void {
        for (var i = 0; i < keys.size(); i++) {
            NearbyWorkCount.iteration();
            covered[keys[i] as String] = true;
        }
    }
}
