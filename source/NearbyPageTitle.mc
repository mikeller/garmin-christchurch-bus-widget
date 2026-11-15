import Toybox.Lang;
import Toybox.Graphics;

// Title layout is computed once in onLayout, never while drawing departure
// rows. The parenthesised distance is an indivisible suffix.
class NearbyPageTitle {
    // The favourite header draws with FONT_SYSTEM_SMALL. On Descent Mk1 the
    // smaller system fonts visibly have a different weight, and there is no
    // custom font or API-level 3 vector-font weight selection. Preserve the
    // same bold face on both lines; truncate the name rather than the distance
    // if this one font cannot fit the title in two lines.
    static function fonts() as Array<Graphics.FontType> {
        return [Graphics.FONT_SYSTEM_SMALL];
    }

    static function text(name as String, distance as String?) as String {
        return distance == null ? name : name + " (" + (distance as String) + ")";
    }

    // Injectable width measurement for the pure layout tests.
    static function fit(name as String, distance as String?, firstWidth as Number,
                        secondWidth as Number, measure) as Array<String>? {
        return fitMeasured(name, distance, firstWidth, secondWidth, measure, null,
            Graphics.FONT_XTINY);
    }

    static function fitDc(name as String, distance as String?, firstWidth as Number,
                          secondWidth as Number, dc as Dc,
                          font as Graphics.FontType) as Array<String>? {
        return fitMeasured(name, distance, firstWidth, secondWidth, null, dc, font);
    }

    static function truncate(name as String, distance as String?, firstWidth as Number,
                             secondWidth as Number, measure) as Array<String>? {
        return truncateMeasured(name, distance, firstWidth, secondWidth, measure, null,
            Graphics.FONT_XTINY);
    }

    static function truncateDc(name as String, distance as String?, firstWidth as Number,
                               secondWidth as Number, dc as Dc,
                               font as Graphics.FontType) as Array<String>? {
        return truncateMeasured(name, distance, firstWidth, secondWidth, null, dc, font);
    }

    private static function width(text as String, measure, dc as Dc?,
                                  font as Graphics.FontType) as Number {
        return dc != null ? (dc as Dc).getTextWidthInPixels(text, font) :
            measure.width(text) as Number;
    }

    private static function fitMeasured(name as String, distance as String?,
                                        firstWidth as Number, secondWidth as Number,
                                        measure, dc as Dc?,
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
        if (distance != null && width(name, measure, dc, font) <= firstWidth) {
            return [name, distanceOnly];
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
                if (orphanedShortWord(first, name.substring(i + 1, name.length()) as String)) {
                    balance += 10000;
                }
                if (balance < bestBalance) {
                    best = [first, second];
                    bestBalance = balance;
                }
            }
        }
        if (best != null) {
            return best;
        }
        return null;
    }

    private static function orphanedShortWord(first as String, secondName as String) as Boolean {
        var last = 0;
        for (var i = 0; i < first.length(); i++) {
            if (" ".equals(first.substring(i, i + 1))) {
                last = i + 1;
            }
        }
        var nextSpace = secondName.find(" ");
        var firstWordLength = nextSpace == null ? secondName.length() : nextSpace as Number;
        return (last > 0 && first.length() - last <= 2) || firstWordLength <= 2;
    }

    private static function truncateMeasured(name as String, distance as String?,
                                             firstWidth as Number, secondWidth as Number,
                                             measure, dc as Dc?,
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
