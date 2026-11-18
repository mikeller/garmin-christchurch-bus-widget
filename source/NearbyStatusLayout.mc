import Toybox.Lang;
import Toybox.Graphics;

// Width measurement is supplied by the view so the wrapping logic can be
// tested without a graphics context. Called only while laying out a new view.
(:nearby)
class NearbyStatusLayout {
    static function wrap(text as String, maxWidth as Number, measure as Method, maxLines as Number) as Array<String>? {
        return wrapMeasured(text, maxWidth, measure, null, Graphics.FONT_XTINY, maxLines);
    }

    // Views use the Dc directly. Avoid a dynamically invoked bound method
    // during onLayout, which can throw Invalid Value on older devices.
    static function wrapDc(text as String, maxWidth as Number, dc as Dc,
                           font as Graphics.FontType, maxLines as Number) as Array<String>? {
        return wrapMeasured(text, maxWidth, null, dc, font, maxLines);
    }

    private static function widthOf(text as String, measure as Method?, dc as Dc?,
                                    font as Graphics.FontType) as Number {
        return dc != null ? (dc as Dc).getTextWidthInPixels(text, font) :
            (measure as Method).invoke(text) as Number;
    }

    private static function wrapMeasured(text as String, maxWidth as Number,
                                         measure as Method?, dc as Dc?,
                                         font as Graphics.FontType, maxLines as Number) as Array<String>? {
        var lines = [] as Array<String>;
        var line = "";
        var start = 0;
        while (start < text.length()) {
            var space = (text.substring(start, text.length()) as String).find(" ");
            var end = space == null ? text.length() : start + (space as Number);
            var word = text.substring(start, end) as String;
            start = (end as Number) + 1;
            if (word.length() == 0) {
                continue;
            }
            var candidate = line.length() == 0 ? word : line + " " + word;
            if (widthOf(candidate, measure, dc, font) <= maxWidth) {
                line = candidate;
                continue;
            }
            if (line.length() > 0) {
                lines.add(line);
                line = "";
                if (lines.size() >= maxLines) {
                    return null;
                }
            }
            // Very long translated words may need a break without whitespace.
            while (widthOf(word, measure, dc, font) > maxWidth) {
                var cut = 1;
                if (widthOf(word.substring(0, cut), measure, dc, font) > maxWidth) {
                    return null;
                }
                while (cut < word.length() &&
                    widthOf(word.substring(0, cut + 1), measure, dc, font) <= maxWidth) {
                    cut++;
                }
                lines.add(word.substring(0, cut) as String);
                if (lines.size() >= maxLines) {
                    return null;
                }
                word = word.substring(cut, word.length()) as String;
            }
            line = word;
        }
        if (line.length() > 0) {
            lines.add(line);
        }
        return lines.size() <= maxLines ? lines : null;
    }
}
