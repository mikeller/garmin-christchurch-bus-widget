import Toybox.Graphics;
import Toybox.Lang;

// Both a display context and a test fixture supply getTextWidthInPixels.
class DepartureRowFit {
    static function fit(waitTime as String, route as String?, destination as String?,
                        width as Number, measure) as String {
        var routeText = route != null ? route : "";
        var destinationText = destination != null ? destination : "";
        if (width < 1) {
            width = 1;
        }
        var prefix = waitTime + ": " + routeText;
        var full = prefix + " (" + destinationText + ")";
        if (measure.getTextWidthInPixels(full, Graphics.FONT_XTINY) <= width) {
            return full;
        }
        if (destinationText.length() == 0) {
            return prefix;
        }
        var suffix = "…)";
        var start = prefix + " (";
        // Keep the departure time and route even if a device cannot accommodate
        // the destination at all.
        if (measure.getTextWidthInPixels(start + suffix, Graphics.FONT_XTINY) > width) {
            return prefix;
        }
        var length = destinationText.length();
        while (length > 0) {
            var candidate = start + destinationText.substring(0, length) + suffix;
            if (measure.getTextWidthInPixels(candidate, Graphics.FONT_XTINY) <= width) {
                return candidate;
            }
            length--;
        }
        return start + suffix;
    }
}
