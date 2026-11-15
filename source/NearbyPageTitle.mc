import Toybox.Lang;
import Toybox.Graphics;

// Layout work is done in onLayout, not while drawing departure rows.
(:nearby)
class NearbyPageTitle {
    private static var cachedFonts as Array<Graphics.FontType>?;
    private static var cachedSize as Number = -1;

    static function effectiveFonts(dc as Dc) as Array<Graphics.FontType> {
        var size = dc.getWidth() * 10000 + dc.getHeight();
        if (cachedFonts == null || cachedSize != size) {
            var candidates = fonts();
            var heights = [] as Array<Number>;
            for (var i = 0; i < candidates.size(); i++) {
                heights.add(dc.getFontHeight(candidates[i]));
            }
            cachedFonts = smallerFonts(candidates, heights);
            cachedSize = size;
        }
        return cachedFonts as Array<Graphics.FontType>;
    }

    static function rowsFit(start as Number, lines as Number, titleLineHeight as Number,
                            separatorHeight as Number, rowHeight as Number, screenHeight as Number,
                            bottomWidth as Number) as Boolean {
        var bottom = start + lines * titleLineHeight +
            separatorHeight + 2 * rowHeight;
        return bottom <= screenHeight - 5 && bottomWidth >= 80;
    }

    static function fonts() as Array<Graphics.FontType> {
        return [Graphics.FONT_SYSTEM_SMALL, Graphics.FONT_SYSTEM_TINY,
                Graphics.FONT_SYSTEM_XTINY];
    }

    // Only a strictly shorter font earns a slot; Mk1 XTINY is the same
    // 26 px height as TINY, but regular rather than bold.
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

    static function text(name as String, distance as String?) as String {
        return distance == null ? name : name + " (" + (distance as String) + ")";
    }

    // Kept as a duck-typed width-measurer interface for tests.
    static function fit(name as String, distance as String?, firstWidth as Number,
                        secondWidth as Number, measure) as Array<String>? {
        return fitLines(name, distance, [firstWidth, secondWidth], measure);
    }

    static function fitLines(name as String, distance as String?,
                             widths as Array<Number>, measure) as Array<String>? {
        return fitMeasured(name, distance, widths, measure, null, Graphics.FONT_SYSTEM_SMALL);
    }

    static function fitDc(name as String, distance as String?, widths as Array<Number>,
                          dc as Dc, font as Graphics.FontType) as Array<String>? {
        return fitMeasured(name, distance, widths, null, dc, font);
    }

    private static function width(text as String, measure, dc as Dc?,
                                  font as Graphics.FontType) as Number {
        return dc != null ? (dc as Dc).getTextWidthInPixels(text, font) :
            measure.width(text) as Number;
    }

    // A slash is attached to the preceding word so a break may only follow it.
    // The distance is one word and cannot be split.
    static function splitWords(name as String) as Array<String> {
        var result = [] as Array<String>;
        var start = 0;
        while (start < name.length()) {
            while (start < name.length() && " ".equals(name.substring(start, start + 1))) {
                start++;
            }
            if (start >= name.length()) {
                break;
            }
            var stop = start;
            while (stop < name.length() && !" ".equals(name.substring(stop, stop + 1))) {
                stop++;
            }
            result.add(name.substring(start, stop) as String);
            start = stop;
        }
        return result;
    }

    private static function words(name as String, distance as String?) as Array<String> {
        var displayed = slashName(name);
        var raw = splitWords(displayed);
        var result = [] as Array<String>;
        for (var i = 0; i < raw.size(); i++) {
            var word = raw[i] as String;
            if ("".equals(word)) {
                continue;
            }
            if ("/".equals(word) && result.size() > 0) {
                var last = result.size() - 1;
                result[last] = result[last] + " /";
            } else {
                result.add(word);
            }
        }
        if (distance != null) {
            result.add("(" + (distance as String) + ")");
        }
        return result;
    }

    private static function slashName(name as String) as String {
        var at = name.find(" near ");
        while (at != null) {
            name = name.substring(0, at) + " / " +
                name.substring((at as Number) + 6, name.length());
            at = name.find(" near ");
        }
        return name;
    }

    private static function line(words as Array<String>, start as Number,
                                 end as Number) as String {
        var result = words[start];
        for (var i = start + 1; i < end; i++) {
            result += " " + words[i];
        }
        return result;
    }

    private static function allowedBreak(words as Array<String>, at as Number) as Boolean {
        if (at <= 0 || at >= words.size()) {
            return false;
        }
        if ((words[at] as String).substring(0, 1).equals("(")) {
            return true;
        }
        // Do not separate a street suffix from its street. A trailing slash
        // belongs with the street name and is the preferred break position.
        if (("St".equals(words[at]) || "Rd".equals(words[at])) ||
            ("St".equals(words[at - 1]) || "Rd".equals(words[at - 1]))) {
            return false;
        }
        return true;
    }

    private static function fitMeasured(name as String, distance as String?,
                                        widths as Array<Number>, measure, dc as Dc?,
                                        font as Graphics.FontType) as Array<String>? {
        if (widths.size() == 0 || widths.size() > 3) {
            return null;
        }
        var full = text(name, distance);
        if (widths.size() == 1) {
            return width(full, measure, dc, font) <= widths[0] ? [full] : null;
        }
        var parts = words(name, distance);
        var best = null as Array<String>?;
        var bestScore = 2147483647;
        for (var a = 1; a < parts.size(); a++) {
            if (!allowedBreak(parts, a)) {
                continue;
            }
            var first = line(parts, 0, a);
            var firstWidth = width(first, measure, dc, font);
            if (firstWidth > widths[0]) {
                continue;
            }
            if (widths.size() == 2) {
                var second = line(parts, a, parts.size());
                var secondWidth = width(second, measure, dc, font);
                if (secondWidth <= widths[1]) {
                    var score = firstWidth > secondWidth ?
                        firstWidth - secondWidth : secondWidth - firstWidth;
                    if (score < bestScore) {
                        best = [first, second];
                        bestScore = score;
                    }
                }
            } else {
                for (var b = a + 1; b < parts.size(); b++) {
                    if (!allowedBreak(parts, b)) {
                        continue;
                    }
                    var middle = line(parts, a, b);
                    var last = line(parts, b, parts.size());
                    var middleWidth = width(middle, measure, dc, font);
                    var lastWidth = width(last, measure, dc, font);
                    if (middleWidth <= widths[1] && lastWidth <= widths[2]) {
                        var largest = firstWidth > middleWidth ? firstWidth : middleWidth;
                        largest = largest > lastWidth ? largest : lastWidth;
                        var smallest = firstWidth < middleWidth ? firstWidth : middleWidth;
                        smallest = smallest < lastWidth ? smallest : lastWidth;
                        var score = largest - smallest;
                        if (score < bestScore) {
                            best = [first, middle, last];
                            bestScore = score;
                        }
                    }
                }
            }
        }
        return best;
    }

    // Last resort: reserve a whole line for distance, shorten only the name.
    static function truncateDc(name as String, distance as String?,
                               widths as Array<Number>, dc as Dc,
                               font as Graphics.FontType) as Array<String>? {
        return truncateMeasured(name, distance, widths, null, dc, font);
    }

    static function truncate(name as String, distance as String?,
                             widths as Array<Number>, measure) as Array<String>? {
        return truncateMeasured(name, distance, widths, measure, null,
            Graphics.FONT_SYSTEM_SMALL);
    }

    private static function truncateMeasured(name as String, distance as String?,
                                             widths as Array<Number>, measure, dc as Dc?,
                                             font as Graphics.FontType) as Array<String>? {
        var suffix = distance == null ? null : "(" + (distance as String) + ")";
        var nameLines = suffix == null ? widths.size() : widths.size() - 1;
        if (nameLines < 1 || (suffix != null &&
            width(suffix as String, measure, dc, font) > widths[widths.size() - 1])) {
            return null;
        }
        var displayed = slashName(name);
        var result = [] as Array<String>;
        var remaining = displayed;
        for (var i = 0; i < nameLines; i++) {
            var limit = widths[i];
            if (i + 1 < nameLines) {
                var cut = remaining.length();
                while (cut > 0 && width(remaining.substring(0, cut), measure, dc, font) > limit) {
                    cut--;
                }
                var space = null as Number?;
                for (var j = 0; j < cut; j++) {
                    if (" ".equals(remaining.substring(j, j + 1))) {
                        space = j;
                    }
                }
                if (space != null && space > 0) {
                    cut = space as Number;
                }
                if (cut <= 0) {
                    break;
                }
                result.add(remaining.substring(0, cut) as String);
                remaining = remaining.substring(cut, remaining.length()) as String;
                while (remaining.length() > 0 && " ".equals(remaining.substring(0, 1))) {
                    remaining = remaining.substring(1, remaining.length()) as String;
                }
            } else {
                var cut = remaining.length();
                while (cut > 0 && width(remaining.substring(0, cut) + "...", measure, dc, font) > limit) {
                    cut--;
                }
                if (width(remaining, measure, dc, font) <= limit) {
                    result.add(remaining);
                } else if (cut > 0) {
                    result.add(remaining.substring(0, cut) + "...");
                }
            }
        }
        if (suffix != null) {
            result.add(suffix as String);
        }
        return result.size() > 0 ? result : null;
    }
}
