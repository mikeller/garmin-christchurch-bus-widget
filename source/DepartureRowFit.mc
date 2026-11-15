import Toybox.Graphics;
import Toybox.Lang;

// Both a display context and a test fixture supply getTextWidthInPixels.
class DepartureRowFit {
    // The SYSTEM family is bold on the Descent Mk1. XTINY is regular there.
    private static var cachedFonts as Array<Graphics.FontType>?;
    private static var cachedSize as Number = -1;

    static function effectiveFonts(dc as Dc) as Array<Graphics.FontType> {
        var size = dc.getWidth() * 10000 + dc.getHeight();
        if (cachedFonts == null || cachedSize != size) {
            cachedFonts = smallerFonts(
                [Graphics.FONT_SYSTEM_SMALL, Graphics.FONT_SYSTEM_TINY],
                [dc.getFontHeight(Graphics.FONT_SYSTEM_SMALL),
                 dc.getFontHeight(Graphics.FONT_SYSTEM_TINY)]);
            cachedSize = size;
        }
        return cachedFonts as Array<Graphics.FontType>;
    }

    static function smallerFonts(candidates as Array<Graphics.FontType>,
                                 heights as Array<Number>) as Array<Graphics.FontType> {
        var kept = [] as Array<Graphics.FontType>;
        var lastHeight = 2147483647;
        for (var i = 0; i < candidates.size() && i < heights.size(); i++) {
            if (heights[i] < lastHeight) {
                kept.add(candidates[i]);
                lastHeight = heights[i];
            }
        }
        return kept;
    }

    // rows: [wait, route, destination]; widths: one width array per font.
    // Keep six destination characters (or the entire shorter name) before
    // selecting a larger font. If none qualifies, use the smallest bold font.
    static function chooseFont(rows as Array, widths as Array, fonts as Array<Graphics.FontType>,
                               measure) as Graphics.FontType {
        for (var f = 0; f < fonts.size(); f++) {
            var fits = true;
            var limits = widths[f] as Array<Number>;
            for (var i = 0; i < rows.size(); i++) {
                var row = rows[i] as Array;
                var destination = row[2] as String?;
                var route = row[1] as String?;
                var prefix = (row[0] as String) + ": " + (route != null ? route : "");
                var name = destination != null ? destination : "";
                var minLength = name.length() < 6 ? name.length() : 6;
                var minimum = minLength == name.length() ?
                    prefix + " (" + name + ")" :
                    prefix + " (" + name.substring(0, minLength) + "…)";
                if (limits[i] < 1 ||
                    measure.getTextWidthInPixels(minimum, fonts[f]) > limits[i]) {
                    fits = false;
                    break;
                }
            }
            if (fits) {
                return fonts[f];
            }
        }
        return fonts[fonts.size() - 1];
    }

    static function fit(waitTime as String, route as String?, destination as String?,
                        width as Number, font as Graphics.FontType, measure) as String {
        var routeText = route != null ? route : "";
        var destinationText = destination != null ? destination : "";
        if (width < 1) {
            width = 1;
        }
        var prefix = waitTime + ": " + routeText;
        var full = prefix + " (" + destinationText + ")";
        if (measure.getTextWidthInPixels(full, font) <= width) {
            return full;
        }
        if (destinationText.length() == 0) {
            return prefix;
        }
        var suffix = "…)";
        var start = prefix + " (";
        // Keep the departure time and route even if a device cannot accommodate
        // the destination at all.
        if (measure.getTextWidthInPixels(start + suffix, font) > width) {
            return prefix;
        }
        var length = destinationText.length();
        while (length > 0) {
            var candidate = start + destinationText.substring(0, length) + suffix;
            if (measure.getTextWidthInPixels(candidate, font) <= width) {
                return candidate;
            }
            length--;
        }
        return start + suffix;
    }
}
