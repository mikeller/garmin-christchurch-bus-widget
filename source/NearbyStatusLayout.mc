import Toybox.Lang;

// Width measurement is supplied by the view so the wrapping logic can be
// tested without a graphics context. Called only while laying out a new view.
class NearbyStatusLayout {
    static function wrap(text as String, maxWidth as Number, measure as Method, maxLines as Number) as Array<String>? {
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
            if ((measure.invoke(candidate) as Number) <= maxWidth) {
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
            while ((measure.invoke(word) as Number) > maxWidth) {
                var cut = 1;
                if ((measure.invoke(word.substring(0, cut)) as Number) > maxWidth) {
                    return null;
                }
                while (cut < word.length() &&
                    (measure.invoke(word.substring(0, cut + 1)) as Number) <= maxWidth) {
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
