import Toybox.Lang;

// Pure selection over the borrowed rows and parallel service keys of the
// loaded candidate contexts. No departure rows or per-stop sets are built.
(:nearby)
class NearbyCoverageSelection {
    // Same result shape as NearbyStopMaths.nearestSplit().
    static function select(contexts as Array, lat as Number, lon as Number,
                           favourites as Array<Number>, n as Number) as Array {
        var rows = [] as Array;
        for (var t = 0; t < contexts.size(); t++) {
            var tileRows = (contexts[t] as Dictionary)["s"] as Array;
            for (var r = 0; r < tileRows.size(); r++) {
                rows.add(tileRows[r]);
            }
        }
        // Inconsistent or absent metadata must reproduce the old selection,
        // including favourite distance and tie behaviour.
        var legacy = NearbyStopMaths.nearestSplit(rows, lat, lon, favourites, n);
        if (!NearbyServiceContext.consistent(contexts) || n <= 0) {
            return legacy;
        }
        var chosen = [] as Array;
        var nearby = [] as Array;
        var lastD2 = -1l;
        var lastCode = -1;
        // Visit every candidate in (unrounded squared distance, code) order.
        // At most the loaded tile's validated rows can be examined.
        for (var scan = 0; scan < rows.size() && nearby.size() < n; scan++) {
            var best = -1;
            var bestD2 = 0l;
            var bestCode = 0;
            for (var i = 0; i < rows.size(); i++) {
                var row = rows[i] as Array;
                var code = row[NearbyStopMaths.STOP_CODE] as Number;
                if (isFavourite(favourites, code)) {
                    continue;
                }
                var d2 = NearbyStopMaths.distanceSquared(row[NearbyStopMaths.STOP_LAT_E5] as Number,
                    row[NearbyStopMaths.STOP_LON_E5] as Number, lat, lon);
                if (d2 < lastD2 || (d2 == lastD2 && code <= lastCode)) {
                    continue;
                }
                if (best < 0 || d2 < bestD2 || (d2 == bestD2 && code < bestCode)) {
                    best = i;
                    bestD2 = d2;
                    bestCode = code;
                }
            }
            if (best < 0) {
                break;
            }
            lastD2 = bestD2;
            lastCode = bestCode;
            var keys = keysFor(contexts, best);
            // Null, partial and empty keys never establish coverage.
            if (keys != null && whollyCovered(keys as String, contexts, chosen,
                                               bestD2, favourites, lat, lon)) {
                continue;
            }
            chosen.add(best);
            var selected = rows[best] as Array;
            nearby.add([bestCode, selected[NearbyStopMaths.STOP_NAME],
                NearbyStopMaths.metresFromSquared(bestD2)] as Array);
        }
        return [nearby, legacy[1]] as Array;
    }

    private static function isFavourite(codes as Array<Number>, code as Number) as Boolean {
        for (var i = 0; i < codes.size(); i++) {
            if (codes[i] == code) {
                return true;
            }
        }
        return false;
    }

    // Indices are global across the concatenated borrowed row arrays.
    private static function keysFor(contexts as Array, index as Number) as String? {
        for (var t = 0; t < contexts.size(); t++) {
            var context = contexts[t] as Dictionary;
            var rows = context["s"] as Array;
            if (index >= rows.size()) {
                index -= rows.size();
                continue;
            }
            var keys = (context["i"] as Array)[index] as String?;
            if (keys == null) {
                return null;
            }
            var code = (rows[index] as Array)[NearbyStopMaths.STOP_CODE] as Number;
            var partial = context["p"] as Array;
            for (var p = 0; p < partial.size(); p++) {
                if (partial[p] == code) {
                    return null;
                }
            }
            return keys;
        }
        return null;
    }

    private static function whollyCovered(keys as String, contexts as Array,
                                           chosen as Array,
                                           candidateD2 as Long, favourites as Array<Number>,
                                           lat as Number, lon as Number) as Boolean {
        // Decode only the candidate once. All comparisons use the validated
        // ascending two-digit base36 encoding, never route-name matching.
        var digits = keys.toCharArray();
        // At most five retained stops and sixteen configured favourites.
        // Convert each provider once per candidate, not once per digit pair.
        var providers = [] as Array;
        for (var j = 0; j < chosen.size(); j++) {
            var provider = keysFor(contexts, chosen[j] as Number);
            if (provider != null) {
                providers.add((provider as String).toCharArray());
            }
        }
        var index = 0;
        for (var t = 0; t < contexts.size(); t++) {
            var rows = (contexts[t] as Dictionary)["s"] as Array;
            for (var r = 0; r < rows.size(); r++) {
                var row = rows[r] as Array;
                if (isFavourite(favourites, row[NearbyStopMaths.STOP_CODE] as Number) &&
                    NearbyStopMaths.distanceSquared(row[NearbyStopMaths.STOP_LAT_E5] as Number,
                        row[NearbyStopMaths.STOP_LON_E5] as Number, lat, lon) < candidateD2) {
                    var provider = keysFor(contexts, index);
                    if (provider != null) {
                        providers.add((provider as String).toCharArray());
                    }
                }
                index++;
            }
        }
        for (var k = 0; k < digits.size(); k += 2) {
            var covered = false;
            for (var j = 0; j < providers.size(); j++) {
                if (hasPair(providers[j] as Array, digits[k] as Char, digits[k + 1] as Char)) {
                    covered = true;
                    break;
                }
            }
            if (!covered) {
                return false;
            }
        }
        return true;
    }

    private static function hasPair(digits as Array, high as Char, low as Char) as Boolean {
        for (var i = 0; i < digits.size(); i += 2) {
            if (digits[i] == high && digits[i + 1] == low) {
                return true;
            }
        }
        return false;
    }
}
