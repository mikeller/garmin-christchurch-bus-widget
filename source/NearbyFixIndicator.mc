import Toybox.Lang;

(:nearby)
class NearbyFixIndicator {
    // [x, y, width, height], or null where the top chord is too narrow.
    // The existing network icon remains centred at width / 2 - 10, y=4.
    static function rect(width as Number, height as Number,
                         networkIcon as Boolean) as Array<Number>? {
        var y = height / 14;
        var x = width / 2 - (networkIcon ? 29 : 6);
        var radius = width / 2 - 5;
        var offset = y - height / 2;
        var chordSquared = radius * radius - offset * offset;
        // Conservative integer comparison: at least 80 px of chord at the
        // top edge, including an 8 px horizontal safety margin.
        if (width < 120 || height < 120 || chordSquared < 1600 ||
            x < width / 2 - 36 || x + 12 > width / 2 + 36) {
            return null;
        }
        return [x, y, 12, 12];
    }
}
