import Toybox.Lang;

// Pure glance title selection. Never loads a tile or needs nearby-only code.
(:glance)
class NearbyGlanceTitle {
    static function isBlank(value as String?) as Boolean {
        if (value == null) {
            return true;
        }
        var text = value as String;
        for (var i = 0; i < text.length(); i++) {
            if (" \t\r\n".find(text.substring(i, i + 1)) == null) {
                return false;
            }
        }
        return true;
    }

    static function title(configured as String?, cached as String?, code as Number,
                          fallback as String) as String {
        if (!isBlank(configured)) {
            return trim(configured as String);
        }
        if (!isBlank(cached)) {
            return trim(cached as String);
        }
        return Lang.format(fallback, [code]);
    }

    private static function trim(text as String) as String {
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
}
