import Toybox.Lang;

(:nearby)
class NearbyPageNames {
    static function hasConfiguredName(name as String?) as Boolean {
        return name != null && !"".equals(trimWhitespace(name as String));
    }

    // Pure title decision; the glance can reuse this without acquiring a
    // position or modifying the configured favourite name.
    static function favouriteTitle(configured as String?, code as Number,
                                   tileRows as Array?, fallbackFormat as String) as String {
        if (configured != null) {
            var name = trimWhitespace(configured as String);
            if (!"".equals(name)) {
                return name;
            }
        }
        if (tileRows != null) {
            var tileName = displayTileName(code, tileRows as Array);
            if (tileName != null && !"".equals(tileName as String)) {
                return tileName as String;
            }
        }
        return Lang.format(fallbackFormat, [code]);
    }

    private static function trimWhitespace(text as String) as String {
        var first = 0;
        var last = text.length();
        while (first < last && " \t\r\n".find(text.substring(first, first + 1)) != null) {
            first++;
        }
        while (last > first && " \t\r\n".find(text.substring(last - 1, last)) != null) {
            last--;
        }
        return text.substring(first, last) as String;
    }

    private static function displayTileName(code as Number, rows as Array) as String? {
        var raw = null as String?;
        for (var i = 0; i < rows.size(); i++) {
            var row = rows[i];
            if (row instanceof Array && (row as Array).size() == 4 &&
                (row as Array)[0] instanceof Number && (row as Array)[0] == code &&
                (row as Array)[3] instanceof String) {
                raw = (row as Array)[3] as String;
                break;
            }
        }
        if (raw == null) {
            return null;
        }
        var cleanName = clean(raw as String);
        for (var i = 0; i < rows.size(); i++) {
            var other = rows[i];
            if (other instanceof Array && (other as Array).size() == 4 &&
                (other as Array)[0] instanceof Number && (other as Array)[0] != code &&
                (other as Array)[3] instanceof String &&
                cleanName.equals(clean((other as Array)[3] as String))) {
                return raw;
            }
        }
        return cleanName;
    }

    static function clean(name as String) as String {
        return SharedStopName.clean(name);
    }

    (:nearby)
    static function displayName(entry as Array, nearby as Array) as String {
        var raw = entry[NearbyStopMaths.ENTRY_NAME] as String;
        var cleanName = clean(raw);
        for (var i = 0; i < nearby.size(); i++) {
            var other = nearby[i] as Array;
            if (other[NearbyStopMaths.ENTRY_CODE] != entry[NearbyStopMaths.ENTRY_CODE] &&
                cleanName.equals(clean(other[NearbyStopMaths.ENTRY_NAME] as String))) {
                return raw;
            }
        }
        return cleanName;
    }

    (:nearby)
    static function distance(metres as Number) as String {
        if (metres < 1000) {
            return metres.toString() + " m";
        }
        // Round to the nearest 100 m, half up. Keep one decimal at 3 km too.
        var tenths = (metres + 50) / 100;
        return (tenths / 10).toString() + "." + (tenths % 10).toString() + " km";
    }
}
