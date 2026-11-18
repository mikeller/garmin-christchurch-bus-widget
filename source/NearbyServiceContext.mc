import Toybox.Lang;

// Borrowed tile arrays; no decoded per-stop sets. A missing context means
// every stop is unknown, never an empty complete set.
(:nearby)
class NearbyServiceContext {
    static const MAX_STOPS = 292;
    static const MAX_BYTES = 4096;

    // The SDK has already parsed JSON by the time this runs. This bounded
    // lower bound catches oversized parsed fixtures without serialising the
    // tile or allocating a second body. Escaped names and unknown root keys
    // cannot be measured accurately here; the producer enforces the wire cap.
    static function minimumCoreBytes(tile as Dictionary) as Number {
        var rows = tile["s"] as Array;
        if (rows.size() > MAX_STOPS) {
            return MAX_BYTES + 1;
        }
        var minimum = 20;
        for (var j = 0; j < rows.size(); j++) {
            var row = rows[j] as Array;
            minimum += (row[0] as Number).toString().length() +
                (row[1] as Number).toString().length() +
                (row[2] as Number).toString().length() +
                (row[3] as String).length() + 8;
            if (minimum > MAX_BYTES) {
                return minimum;
            }
        }
        return minimum;
    }

    static function plausibleBody(tile as Dictionary) as Boolean {
        return minimumCoreBytes(tile) <= MAX_BYTES;
    }

    static function usable(tile as Dictionary) as Boolean {
        var rows = tile["s"] as Array;
        var count = rows.size();
        var k = tile["K"];
        var digest = tile["sh"];
        var indexes = tile["i"];
        var partial = tile["p"];
        if (!(tile["m"] instanceof Number) || tile["m"] != 2 ||
            !(k instanceof Number) || (k as Number) < 1 || (k as Number) > 1296 ||
            !(digest instanceof String) || (digest as String).length() != 64 ||
            !(indexes instanceof Array) || (indexes as Array).size() != count ||
            !(partial instanceof Array) || (partial as Array).size() > count ||
            !plausibleBody(tile)) {
            return false;
        }
        var hex = (digest as String).toCharArray();
        for (var j = 0; j < hex.size(); j++) {
            var ch = (hex[j] as Char).toNumber();
            if (!((ch >= 48 && ch <= 57) || (ch >= 97 && ch <= 102))) {
                return false;
            }
        }
        // Lower bound includes fixed JSON metadata punctuation and digest.
        // This is not a substitute for the producer's exact UTF-8 wire cap.
        var minimum = minimumCoreBytes(tile) + 100;
        for (var j = 0; j < count; j++) {
            var value = (indexes as Array)[j];
            if (value == null) {
                continue;
            }
            if (!(value instanceof String)) {
                return false;
            }
            var length = (value as String).length();
            if (length == 0 || length % 2 != 0 || length > 2 * (k as Number)) {
                return false;
            }
            minimum += length + 2;
            if (minimum > MAX_BYTES) {
                return false;
            }
            // One bounded allocation per encoded stop, not per digit pair.
            var digits = (value as String).toCharArray();
            var previous = -1;
            for (var n = 0; n < length; n += 2) {
                var high = base36(digits[n] as Char);
                var low = base36(digits[n + 1] as Char);
                var id = high * 36 + low;
                if (high < 0 || low < 0 || id <= previous || id >= (k as Number)) {
                    return false;
                }
                previous = id;
            }
        }
        var previousCode = 0;
        for (var j = 0; j < (partial as Array).size(); j++) {
            var code = (partial as Array)[j];
            if (!(code instanceof Number) || (code as Number) <= previousCode ||
                (code as Number) < 1000 || (code as Number) > 99999) {
                return false;
            }
            previousCode = code as Number;
            minimum += previousCode.toString().length() + 1;
            if (minimum > MAX_BYTES) {
                return false;
            }
            var found = false;
            for (var n = 0; n < count; n++) {
                var row = rows[n] as Array;
                if (row[0] == code && (indexes as Array)[n] != null) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }
        return true;
    }

    private static function base36(value as Char) as Number {
        var n = value.toNumber();
        if (n >= 48 && n <= 57) {
            return n - 48;
        }
        if (n >= 97 && n <= 122) {
            return n - 87;
        }
        return -1;
    }

    static function context(tile as Dictionary, fresh as Boolean) as Dictionary {
        var usableMetadata = fresh && usable(tile);
        return {"s" => tile["s"], "g" => tile["g"],
                "sh" => usableMetadata ? tile["sh"] : null,
                "K" => usableMetadata ? tile["K"] : null,
                "i" => usableMetadata ? tile["i"] : null,
                "p" => usableMetadata ? tile["p"] : null} as Dictionary;
    }

    // Validate ALL loaded candidates before comparing any global IDs.
    static function consistent(candidates as Array) as Boolean {
        if (candidates.size() == 0) {
            return false;
        }
        var first = candidates[0];
        if (!(first instanceof Dictionary) || !((first as Dictionary)["sh"] instanceof String) ||
            !((first as Dictionary)["K"] instanceof Number) ||
            !((first as Dictionary)["g"] instanceof String)) {
            return false;
        }
        for (var j = 0; j < candidates.size(); j++) {
            var candidate = candidates[j];
            if (!(candidate instanceof Dictionary) ||
                !((candidate as Dictionary)["sh"] instanceof String) ||
                !((candidate as Dictionary)["K"] instanceof Number) ||
                !((candidate as Dictionary)["g"] instanceof String) ||
                !((first as Dictionary)["sh"] as String).equals((candidate as Dictionary)["sh"]) ||
                (first as Dictionary)["K"] != (candidate as Dictionary)["K"] ||
                !((first as Dictionary)["g"] as String).equals((candidate as Dictionary)["g"])) {
                return false;
            }
        }
        return true;
    }
}
