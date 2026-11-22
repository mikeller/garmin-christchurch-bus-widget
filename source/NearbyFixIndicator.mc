import Toybox.Lang;
import Toybox.Graphics;

(:nearby)
class NearbyFixIndicator {
    static const PIN_COLOUR as Number = Graphics.COLOR_YELLOW;
    static const SLASH_COLOUR as Number = Graphics.COLOR_BLACK;
    static const SCALE_DIVISOR as Number = 9;
    static const MIN_DIAMETER as Number = 20;
    static const TITLE_GAP as Number = 2;
    // A lone 20 px bitmap cannot fit above the old height / 10 favourite
    // title inside a 240 px round screen without four extra pixels.
    static const NETWORK_TITLE_SHIFT as Number = 4;
    // This PNG is 20 x 20 px in resources/drawables/connection_problem_icon.png.
    static const NETWORK_SIZE as Number = 20;
    static const NETWORK_GAP as Number = 4;
    static const GPS_FIRST as Boolean = true;

    // Pure layout: [GPS left, GPS top, diameter, network left, network top].
    // Unused icon coordinates are -1. Centre each single icon or the whole
    // pair; both icons share one vertical centre line.
    static function rect(width as Number, height as Number,
                         titleTop as Number, round as Boolean,
                         gpsIcon as Boolean, networkIcon as Boolean) as Array<Number>? {
        if (!gpsIcon && !networkIcon) {
            return null;
        }
        var size = width / SCALE_DIVISOR;
        if (size < MIN_DIAMETER) {
            size = MIN_DIAMETER;
        }
        var rowHeight = gpsIcon && size > NETWORK_SIZE ? size : NETWORK_SIZE;
        var rowTop = titleTop - rowHeight - TITLE_GAP;
        var gpsX = -1;
        var gpsY = -1;
        var networkX = -1;
        var networkY = -1;
        if (gpsIcon && networkIcon) {
            var pairLeft = (width - size - NETWORK_GAP - NETWORK_SIZE) / 2;
            gpsX = GPS_FIRST ? pairLeft : pairLeft + NETWORK_SIZE + NETWORK_GAP;
            networkX = GPS_FIRST ? pairLeft + size + NETWORK_GAP : pairLeft;
        } else if (gpsIcon) {
            gpsX = (width - size) / 2;
        } else {
            networkX = (width - NETWORK_SIZE) / 2;
        }
        if (gpsIcon) {
            gpsY = rowTop + (rowHeight - size) / 2;
        }
        if (networkIcon) {
            networkY = rowTop + (rowHeight - NETWORK_SIZE) / 2;
        }
        if (rowTop < 0 || rowTop + rowHeight + TITLE_GAP > titleTop ||
            (gpsIcon && (gpsX < 0 || gpsX + size > width)) ||
            (networkIcon && (networkX < 0 || networkX + NETWORK_SIZE > width))) {
            return null;
        }
        if (round) {
            var radius = width / 2 - 5;
            if (gpsIcon) {
                var gpsSide = gpsX < width / 2 - size / 2 ?
                    width / 2 - gpsX : gpsX + size - width / 2;
                var gpsOffset = height / 2 - gpsY;
                if (gpsOffset * gpsOffset + gpsSide * gpsSide > radius * radius) {
                    return null;
                }
            }
            if (networkIcon) {
                var networkSide = networkX < width / 2 - NETWORK_SIZE / 2 ?
                    width / 2 - networkX : networkX + NETWORK_SIZE - width / 2;
                var networkOffset = height / 2 - networkY;
                if (networkOffset * networkOffset + networkSide * networkSide >
                    radius * radius) {
                    return null;
                }
            }
        }
        return [gpsX, gpsY, size, networkX, networkY];
    }

    // Shared by nearby and favourite pages. Layout is cached in onLayout;
    // this draw routine does not allocate or inspect Storage.
    static function draw(dc as Dc, bounds as Array<Number>) as Void {
        var x = bounds[0];
        var y = bounds[1];
        var size = bounds[2];
        var centreX = x + size / 2;
        var centreY = y + size / 2;
        var unit = size / 10;

        // Yellow matches the warning state and remains visible in daylight.
        dc.setColor(PIN_COLOUR, Constants.COLOUR_BACKGROUND);
        dc.setPenWidth(unit);
        // A simple location pin fits within the same 80% square as the network
        // bitmap. The circular head and tapered point stay legible at 20 px.
        var headY = centreY - 2 * unit;
        dc.drawCircle(centreX, headY, 2 * unit);
        dc.drawLine(centreX - 2 * unit, headY, centreX, centreY + 4 * unit);
        dc.drawLine(centreX + 2 * unit, headY, centreX, centreY + 4 * unit);
        // A bold slash means the location is unavailable or not current.
        dc.setColor(SLASH_COLOUR, Constants.COLOUR_BACKGROUND);
        dc.setPenWidth(unit + 1);
        dc.drawLine(centreX - 4 * unit, centreY + 4 * unit,
            centreX + 4 * unit, centreY - 4 * unit);
        dc.setPenWidth(1);
        dc.setColor(Constants.COLOUR_FOREGROUND, Constants.COLOUR_BACKGROUND);
    }
}
