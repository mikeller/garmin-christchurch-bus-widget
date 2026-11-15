import Toybox.Lang;
import Toybox.Math;

// Pure integer maths for nearby-stop discovery ("Departures near me").
//
// Coordinates are integers in 1e-5 degrees (E5), rounded half up, as defined
// by the stop tile contract v1. Degrees from the position API must be kept as
// Double: Float (about 4e-6 degree resolution) is too coarse for E5.
//
// A stop is an Array [stopCode as Number, latE5 as Number, lonE5 as Number,
// name as String], exactly as in a tile's "s" array.
//
// A result entry is an Array [stopCode, name, metres] (see ENTRY_*). A page
// entry is an Array [stopCode, name, metres, isFavourite] (see PAGE_*), where
// name is null for a favourite (the tile name is not used for favourites) and
// metres is null when the distance is unknown.
(:nearby)
class NearbyStopMaths {
    // Maximum fixed by the tile contract (15 stops per tile was sized for 5).
    // Raising this limit requires revisiting the tile minimum.
    static const NEARBY_COUNT as Number = 5;

    // Indices into a result entry.
    static const ENTRY_CODE as Number = 0;
    static const ENTRY_NAME as Number = 1;
    static const ENTRY_METRES as Number = 2;

    // Indices into a page entry.
    static const PAGE_CODE as Number = 0;
    static const PAGE_NAME as Number = 1;
    static const PAGE_METRES as Number = 2;
    static const PAGE_IS_FAVOURITE as Number = 3;

    // Indices into a tile stop.
    static const STOP_CODE as Number = 0;
    static const STOP_LAT_E5 as Number = 1;
    static const STOP_LON_E5 as Number = 2;
    static const STOP_NAME as Number = 3;

    // The number of E5 units per tile edge (tile id is floorDiv(e5, 1000)).
    static const TILE_SIZE_E5 as Number = 1000;

    // Longitude scale at Christchurch (cos 43.5 degrees = 0.725) as a ratio
    // LON_SCALE_NUM / LON_SCALE_DEN. The distance is kept exact in Long:
    //   d2 = (dLatE5 * 1000)^2 + (dLonE5 * 725)^2
    // which is the squared distance (in E5^2) of dLat and dLon * 0.725,
    // multiplied by 1e6. Do not divide by 1000 before squaring: the integer
    // division would change the ordering, and it would not match the shared
    // test vectors.
    static const LAT_SCALE as Long = 1000l;
    static const LON_SCALE as Long = 725l;

    // Metres per E5 unit of latitude (about 111.2 km per degree).
    static const METRES_PER_E5 as Double = 1.112d;

    // Each delta is clamped to this many E5 units (20 degrees, about 2200 km)
    // before scaling, so d2 stays below 6.2e18 and cannot overflow a Long
    // (maximum 9.22e18) even for a corrupt tile or a bad fix. Real tiles span
    // about 1 km plus a buffer of at most 3 km, so the clamp never changes a
    // genuine result; beyond it distances are merely understated.
    static const MAX_DELTA_E5 as Number = 2000000;

    // Rounds degrees (a Double, never a Float) to E5, half up:
    // floor(degrees * 100000 + 0.5). No Math.floor: it returns a Float, which
    // cannot hold a 8 digit integer exactly.
    static function toE5(degrees as Double) as Number {
        var scaled = degrees * 100000.0d + 0.5d;
        var truncated = scaled.toLong();
        if (truncated.toDouble() > scaled) {
            // Negative value with a fraction: truncation went the wrong way.
            truncated -= 1l;
        }

        return truncated.toNumber();
    }

    // Mathematical floor division (toward negative infinity) for b > 0.
    // Monkey C integer division truncates toward zero.
    static function floorDiv(a as Number, b as Number) as Number {
        var q = a / b;
        if (a % b < 0) {
            q -= 1;
        }

        return q;
    }

    // Tile id of an E5 position as [ty, tx]. Rounds to E5 first (the inputs
    // are already E5), then floors; never derive it from degrees.
    static function tileId(latE5 as Number, lonE5 as Number) as Array<Number> {
        return [floorDiv(latE5, TILE_SIZE_E5), floorDiv(lonE5, TILE_SIZE_E5)];
    }

    // Exact scaled squared distance (see LAT_SCALE) between two E5 points.
    static function distanceSquared(latE5a as Number, lonE5a as Number, latE5b as Number, lonE5b as Number) as Long {
        var dLat = clampDelta(latE5a - latE5b).toLong() * LAT_SCALE;
        var dLon = clampDelta(lonE5a - lonE5b).toLong() * LON_SCALE;

        return dLat * dLat + dLon * dLon;
    }

    // Approximate distance in whole metres from a distanceSquared() value:
    // sqrt(d2) is in E5 * 1000, one E5 unit is 1.112 m.
    static function metresFromSquared(d2 as Long) as Number {
        return (Math.sqrt(d2.toDouble()) * (METRES_PER_E5 / 1000.0d) + 0.5d).toNumber();
    }

    // Approximate distance in whole metres between two E5 points.
    static function approxMetres(latE5a as Number, lonE5a as Number, latE5b as Number, lonE5b as Number) as Number {
        return metresFromSquared(distanceSquared(latE5a, lonE5a, latE5b, lonE5b));
    }

    // True if the two points are further apart than the given metres, using
    // the same approximation as approxMetres() but without rounding.
    static function movedMoreThan(latE5a as Number, lonE5a as Number, latE5b as Number, lonE5b as Number, metres as Number) as Boolean {
        var threshold = metres.toDouble() * 1000.0d / METRES_PER_E5;

        return distanceSquared(latE5a, lonE5a, latE5b, lonE5b).toDouble() > threshold * threshold;
    }

    // The nearest (up to n) stops, nearest first, ties broken by the lower
    // stop code. Returns [stopCode, name, metres] entries. n larger than the
    // number of stops returns all of them; an empty array returns [].
    static function nearest(stops as Array, latE5 as Number, lonE5 as Number, n as Number) as Array {
        return selectNearest(stops, latE5, lonE5, n, null);
    }

    // Favourite-and-nearby split. Returns [nonFavouriteNearby,
    // favouriteNearby]:
    //  - nonFavouriteNearby: up to n NON-favourite stops, nearest first, as
    //    [stopCode, name, metres] entries;
    //  - favouriteNearby: each favourite that is among the n nearest stops of
    //    the tile overall (favourites included), nearest first, as
    //    [stopCode, name, metres] entries.
    // favouriteCodes is the configured favourites as stop code Numbers
    // (16 at most). Two bounded passes, no full sort.
    static function nearestSplit(stops as Array, latE5 as Number, lonE5 as Number, favouriteCodes as Array<Number>, n as Number) as Array {
        var nonFavourites = selectNearest(stops, latE5, lonE5, n, favouriteCodes);

        var overall = selectNearest(stops, latE5, lonE5, n, null);
        var favouriteNearby = [] as Array;
        for (var i = 0; i < overall.size(); i++) {
            var entry = overall[i] as Array;
            if (contains(favouriteCodes, entry[ENTRY_CODE] as Number)) {
                favouriteNearby.add(entry);
            }
        }

        return [nonFavourites, favouriteNearby] as Array;
    }

    // Page order: the first min(n, F) favourites in configured order, then the
    // non-favourite nearby stops, then the remaining favourites.
    // favourites are the configured stop codes, nonFavouriteNearby and
    // favouriteNearby are the two results of nearestSplit(). A favourite page
    // entry carries its metres only if it is in favouriteNearby, else null.
    static function buildPageOrder(favourites as Array<Number>, nonFavouriteNearby as Array, favouriteNearby as Array, n as Number) as Array {
        var pages = [] as Array;
        var leading = n < 0 ? 0 : n;
        if (leading > favourites.size()) {
            leading = favourites.size();
        }

        for (var i = 0; i < leading; i++) {
            pages.add(favouritePage(favourites[i], favouriteNearby));
        }

        for (var i = 0; i < nonFavouriteNearby.size(); i++) {
            var entry = nonFavouriteNearby[i] as Array;
            pages.add([entry[ENTRY_CODE], entry[ENTRY_NAME], entry[ENTRY_METRES], false] as Array);
        }

        for (var i = leading; i < favourites.size(); i++) {
            pages.add(favouritePage(favourites[i], favouriteNearby));
        }

        return pages;
    }

    private static function favouritePage(code as Number, favouriteNearby as Array) as Array {
        var metres = null;
        for (var i = 0; i < favouriteNearby.size(); i++) {
            var entry = favouriteNearby[i] as Array;
            if ((entry[ENTRY_CODE] as Number) == code) {
                metres = entry[ENTRY_METRES];
                break;
            }
        }

        return [code, null, metres, true] as Array;
    }

    // Bounded insertion selection of the n nearest stops (skipping any stop
    // whose code is in skipCodes, if given). Memory: three arrays of at most
    // n elements plus the result entries.
    private static function selectNearest(stops as Array, latE5 as Number, lonE5 as Number, n as Number, skipCodes as Array<Number>?) as Array {
        var result = [] as Array;
        if (n <= 0) {
            return result;
        }

        // Parallel arrays kept sorted by (d2, code), nearest first.
        var best = [] as Array;
        var bestD2 = [] as Array<Long>;
        var bestCode = [] as Array<Number>;

        for (var i = 0; i < stops.size(); i++) {
            var stop = stops[i] as Array;
            var code = stop[STOP_CODE] as Number;
            if (skipCodes != null && contains(skipCodes, code)) {
                continue;
            }

            var d2 = distanceSquared(stop[STOP_LAT_E5] as Number, stop[STOP_LON_E5] as Number, latE5, lonE5);

            // Find the insertion position: after every entry that is nearer,
            // or equally near with a lower code.
            var count = bestD2.size();
            var pos = count;
            while (pos > 0 && (d2 < bestD2[pos - 1] || (d2 == bestD2[pos - 1] && code < bestCode[pos - 1]))) {
                pos--;
            }

            if (pos >= n) {
                continue;
            }

            // Grow until n entries are held; once full, the last (furthest)
            // entry is overwritten by the shift below.
            var last = n - 1;
            if (count < n) {
                best.add(stop);
                bestD2.add(d2);
                bestCode.add(code);
                last = count;
            }

            for (var j = last; j > pos; j--) {
                best[j] = best[j - 1];
                bestD2[j] = bestD2[j - 1];
                bestCode[j] = bestCode[j - 1];
            }
            best[pos] = stop;
            bestD2[pos] = d2;
            bestCode[pos] = code;
        }

        for (var i = 0; i < best.size(); i++) {
            var stop = best[i] as Array;
            result.add([stop[STOP_CODE], stop[STOP_NAME], metresFromSquared(bestD2[i])] as Array);
        }

        return result;
    }

    private static function contains(codes as Array<Number>, code as Number) as Boolean {
        for (var i = 0; i < codes.size(); i++) {
            if (codes[i] == code) {
                return true;
            }
        }

        return false;
    }

    private static function clampDelta(delta as Number) as Number {
        if (delta > MAX_DELTA_E5) {
            return MAX_DELTA_E5;
        }
        if (delta < -MAX_DELTA_E5) {
            return -MAX_DELTA_E5;
        }

        return delta;
    }
}
