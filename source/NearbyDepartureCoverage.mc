import Toybox.Lang;

// A departure is shared only when both the published line and destination
// match exactly. Unknown, empty and error responses do not establish coverage.
(:nearby)
class NearbyDepartureCoverage {
    static const MAX_VISITS = 32;
    static const MAX_SESSION_KEYS = 32;

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
            var rawLine = (visit as Dictionary)["PublishedLineName"];
            var rawDestination = (visit as Dictionary)["DestinationName"];
            if (!(rawLine instanceof String) || !(rawDestination instanceof String)) {
                return null;
            }
            var line = trimField(rawLine as String);
            var destination = trimField(rawDestination as String);
            if (line.length() == 0 || destination.length() == 0) {
                return null;
            }
            // Length-prefix the first field so any punctuation in either
            // field remains unambiguous. Do not case-fold or truncate names.
            var key = line.length().toString() + ":" + line + destination;
            if (!seen.hasKey(key)) {
                seen[key] = true;
                result.add(key);
            }
        }
        return result;
    }

    // Monkey C String has no trim(). Keep the source fields unchanged, and
    // normalise only surrounding whitespace before making a coverage key.
    private static function trimField(value as String) as String {
        var start = 0;
        var end = value.length();
        while (start < end && " \t\n\r\f".find(value.substring(start, start + 1)) != null) {
            start++;
        }
        while (end > start && " \t\n\r\f".find(value.substring(end - 1, end)) != null) {
            end--;
        }
        return value.substring(start, end);
    }

    // Entry index 2 holds accumulated keys, index 6 their membership
    // dictionary, and index 7 a sticky overflow flag. Never use an incomplete
    // union to suppress a stop after the per-session cap is exceeded.
    static function observe(entry as Array, data as Dictionary?) as Boolean {
        if (entry[7] == true) {
            return false;
        }
        if (data != null && data["ErrorCondition"] == null) {
            var visits = data["MonitoredStopVisit"];
            if (visits instanceof Array && (visits as Array).size() > MAX_VISITS) {
                return overflow(entry);
            }
        }
        return mergeInto(entry, keys(data));
    }

    // A cache-hit callback may fire synchronously during page construction.
    // Only completed network responses are observed here; the cache seeder
    // handles cache hits outside the tile/display callback.
    static function observeResponse(candidates as Array, favourites as Array,
                                    id as Number, data as Dictionary?,
                                    completed as Boolean, stale as Boolean,
                                    live as Boolean) as Boolean {
        if (!completed || stale || !live) {
            return false;
        }
        for (var group = 0; group < 2; group++) {
            var entries = group == 0 ? candidates : favourites;
            for (var i = 0; i < entries.size(); i++) {
                var entry = entries[i] as Array;
                if (entry[0] == id) {
                    entry[8] = true;
                    return observe(entry, data);
                }
            }
        }
        return false;
    }

    private static function overflow(entry as Array) as Boolean {
        entry[2] = null;
        entry[6] = {} as Dictionary<String, Boolean>;
        entry[7] = true;
        return true;
    }

    // Merge only completed responses; a no-info response cannot revoke
    // already observed keys unless the response exceeds the safety bound.
    static function mergeInto(entry as Array, fresh as Array?) as Boolean {
        if (fresh == null || entry[7] == true) {
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
                if ((accumulated as Array).size() >= MAX_SESSION_KEYS) {
                    return overflow(entry);
                }
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
