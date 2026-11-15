import Toybox.Graphics;
import Toybox.Lang;

// Width measurement is injected so the fitting policy can be tested without a display.
class DepartureRowFit {
    static function fit(waitTime as String, route as String, destination as String,
                        width as Number, measure as Method) as Array {
        var prefix = waitTime + ": " + route;
        var full = prefix + " (" + destination + ")";
        var fonts = [Graphics.FONT_SYSTEM_TINY, Graphics.FONT_XTINY];
        for (var i = 0; i < fonts.size(); i++) {
            if (measure.invoke(fonts[i], full) <= width) {
                return [full, fonts[i]];
            }
        }

        var font = Graphics.FONT_XTINY;
        var suffix = "…)";
        var start = prefix + " (";
        // Keep the departure time and route even if a device cannot accommodate
        // the destination at all.
        if (measure.invoke(font, start + suffix) > width) {
            return [prefix, font];
        }
        var length = destination.length();
        while (length > 0) {
            var candidate = start + destination.substring(0, length) + suffix;
            if (measure.invoke(font, candidate) <= width) {
                return [candidate, font];
            }
            length--;
        }
        return [start + suffix, font];
    }
}
