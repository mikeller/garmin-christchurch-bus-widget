import Toybox.Lang;
import Toybox.Graphics;

// Title layout is computed once in onLayout, never while drawing departure
// rows. The parenthesised distance is an indivisible suffix.
class NearbyPageTitle {
    static function text(name as String, distance as String?) as String {
        return distance == null ? name : name + " (" + (distance as String) + ")";
    }

    // Injectable width measurement for the pure layout tests.
    static function fit(name as String, distance as String?, firstWidth as Number,
                        secondWidth as Number, measure as Method) as Array<String>? {
        return fitMeasured(name, distance, firstWidth, secondWidth, measure, null,
            Graphics.FONT_XTINY);
    }

    static function fitDc(name as String, distance as String?, firstWidth as Number,
                          secondWidth as Number, dc as Dc,
                          font as Graphics.FontType) as Array<String>? {
        return fitMeasured(name, distance, firstWidth, secondWidth, null, dc, font);
    }

    static function truncate(name as String, distance as String?, firstWidth as Number,
                             secondWidth as Number, measure as Method) as Array<String>? {
        return truncateMeasured(name, distance, firstWidth, secondWidth, measure, null,
            Graphics.FONT_XTINY);
    }

    static function truncateDc(name as String, distance as String?, firstWidth as Number,
                               secondWidth as Number, dc as Dc,
                               font as Graphics.FontType) as Array<String>? {
        return truncateMeasured(name, distance, firstWidth, secondWidth, null, dc, font);
    }

    private static function width(text as String, measure as Method?, dc as Dc?,
                                  font as Graphics.FontType) as Number {
        return dc != null ? (dc as Dc).getTextWidthInPixels(text, font) :
            (measure as Method).invoke(text) as Number;
    }

    private static function fitMeasured(name as String, distance as String?,
                                        firstWidth as Number, secondWidth as Number,
                                        measure as Method?, dc as Dc?,
                                        font as Graphics.FontType) as Array<String>? {
        var full = text(name, distance);
        if (width(full, measure, dc, font) <= firstWidth) {
            return [full];
        }
        var suffix = distance == null ? "" : " (" + (distance as String) + ")";
        // The separator belongs only to a line that also contains name text.
        // A distance alone on the last line has no leading space.
        var distanceOnly = distance == null ? "" : "(" + (distance as String) + ")";
        if (width(distanceOnly, measure, dc, font) > secondWidth) {
            return null;
        }
        // Try complete words first. A break before the suffix preserves its
        // spelling even if the name contains long unbroken GTFS tokens.
        var best = null as Array<String>?;
        var bestBalance = 2147483647;
        for (var i = 0; i < name.length(); i++) {
            if (!" ".equals(name.substring(i, i + 1))) {
                continue;
            }
            var first = name.substring(0, i) as String;
            var second = (name.substring(i + 1, name.length()) as String) + suffix;
            var left = width(first, measure, dc, font);
            var right = width(second, measure, dc, font);
            if (left <= firstWidth && right <= secondWidth) {
                var balance = left > right ? left - right : right - left;
                if (balance < bestBalance) {
                    best = [first, second];
                    bestBalance = balance;
                }
            }
        }
        if (best != null) {
            return best;
        }
        if (distance != null && width(name, measure, dc, font) <= firstWidth) {
            return [name, distanceOnly];
        }
        return null;
    }

    private static function truncateMeasured(name as String, distance as String?,
                                             firstWidth as Number, secondWidth as Number,
                                             measure as Method?, dc as Dc?,
                                             font as Graphics.FontType) as Array<String>? {
        var suffix = distance == null ? "" : "(" + (distance as String) + ")";
        if (distance != null && width(suffix, measure, dc, font) > secondWidth) {
            return null;
        }
        var shortened = name;
        while (shortened.length() > 0 &&
            width(shortened + "...", measure, dc, font) > firstWidth) {
            shortened = shortened.substring(0, shortened.length() - 1);
        }
        var first = shortened + "...";
        if (width(first, measure, dc, font) > firstWidth) {
            return null;
        }
        return distance == null ? [first] : [first, suffix];
    }
}
