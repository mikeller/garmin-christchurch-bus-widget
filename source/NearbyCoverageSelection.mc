import Toybox.Lang;

// Pure selection over the borrowed rows and parallel service keys of the
// loaded candidate contexts. No departure rows or per-stop sets are built.
//
// A loaded tile can validly hold up to NearbyServiceContext.MAX_STOPS (292)
// rows, so the coverage scan below is written to stay close to linear in the
// number of rows: a quadratic-in-rows-times-favourites version of this
// algorithm was measured only against small synthetic fixtures (see
// tools/stoptiles/NEARBY_VALIDATION.md) and tripped the "code executed too
// long" watchdog on a real Descent Mk1 against a real, busier stop cluster.
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

        // A code -> true lookup, built once, instead of a linear favourites
        // scan (up to 16 entries) repeated for every row on every candidate.
        var favouriteSet = {} as Dictionary<Number, Boolean>;
        for (var i = 0; i < favourites.size(); i++) {
            favouriteSet[favourites[i]] = true;
        }

        // Favourites present in the loaded tile, nearest first, with their
        // service keys resolved once. The scan below only ever needs the
        // prefix of this list nearer than the current candidate, and the
        // candidate distance only grows, so each entry becomes a covering
        // provider at most once for the whole call instead of being
        // rediscovered by rescanning every row for every candidate.
        var favouriteD2 = [] as Array<Long>;
        var favouriteKeys = [] as Array;
        for (var index = 0; index < rows.size(); index++) {
            var row = rows[index] as Array;
            var code = row[NearbyStopMaths.STOP_CODE] as Number;
            if (favouriteSet.hasKey(code)) {
                insertFavouriteByDistance(favouriteD2, favouriteKeys,
                    NearbyStopMaths.distanceSquared(row[NearbyStopMaths.STOP_LAT_E5] as Number,
                        row[NearbyStopMaths.STOP_LON_E5] as Number, lat, lon),
                    keysFor(contexts, index));
            }
        }

        var nearby = [] as Array;
        var lastD2 = -1l;
        var lastCode = -1;
        // Keys (as char arrays) of every stop already known to provide
        // coverage: accepted candidates plus favourites nearer than the
        // candidate currently being tested.
        var providers = [] as Array;
        var favouritePtr = 0;
        // Visit every candidate in (unrounded squared distance, code) order.
        // At most the loaded tile's validated rows can be examined.
        for (var scan = 0; scan < rows.size() && nearby.size() < n; scan++) {
            var best = -1;
            var bestD2 = 0l;
            var bestCode = 0;
            for (var i = 0; i < rows.size(); i++) {
                var row = rows[i] as Array;
                var code = row[NearbyStopMaths.STOP_CODE] as Number;
                if (favouriteSet.hasKey(code)) {
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

            while (favouritePtr < favouriteD2.size() && (favouriteD2[favouritePtr] as Long) < bestD2) {
                var provider = favouriteKeys[favouritePtr];
                if (provider != null) {
                    providers.add((provider as String).toCharArray());
                }
                favouritePtr++;
            }

            var keys = keysFor(contexts, best);
            // Null, partial and empty keys never establish coverage.
            if (keys != null && whollyCovered(keys as String, providers)) {
                continue;
            }
            if (keys != null) {
                providers.add((keys as String).toCharArray());
            }
            var selected = rows[best] as Array;
            nearby.add([bestCode, selected[NearbyStopMaths.STOP_NAME],
                NearbyStopMaths.metresFromSquared(bestD2)] as Array);
        }
        return [nearby, legacy[1]] as Array;
    }

    // Inserts (d2, keys) kept sorted ascending by d2. At most favourites.size()
    // entries (16 at most) are ever held, so a plain insertion shift is cheap;
    // this avoids depending on Array.sort(), which is not used elsewhere here.
    private static function insertFavouriteByDistance(d2s as Array<Long>, keys as Array,
                                                       d2 as Long, provider as String?) as Void {
        d2s.add(d2);
        keys.add(provider);
        var pos = d2s.size() - 1;
        while (pos > 0 && (d2s[pos - 1] as Long) > d2) {
            d2s[pos] = d2s[pos - 1];
            keys[pos] = keys[pos - 1];
            pos--;
        }
        d2s[pos] = d2;
        keys[pos] = provider;
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

    // providers are already-resolved char arrays (accepted candidates plus
    // favourites nearer than this candidate); see select().
    private static function whollyCovered(keys as String, providers as Array) as Boolean {
        // Decode only the candidate once. All comparisons use the validated
        // ascending two-digit base36 encoding, never route-name matching.
        var digits = keys.toCharArray();
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
