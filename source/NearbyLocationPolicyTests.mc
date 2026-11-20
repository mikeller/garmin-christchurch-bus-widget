import Toybox.Lang;
import Toybox.Graphics;
import Toybox.Position;
import Toybox.Test;
import Toybox.WatchUi;

(:debug, :nearby)
function nearbyIndicatorWithinOne(a as Number, b as Number) as Boolean {
    var difference = a - b;
    if (difference < 0) {
        difference = -difference;
    }
    return difference <= 1;
}

(:test, :nearby)
function testNearbyLocationPolicy(logger as Logger) as Boolean {
    var now = 5000;
    var missing = NearbyLocationPolicy.decide(Position.QUALITY_NOT_AVAILABLE, now, now);
    Test.assertEqualMessage(false, missing[0], "no position");
    Test.assertEqualMessage(true, missing[2], "acquire without position");
    var exact = NearbyLocationPolicy.decide(Position.QUALITY_GOOD, now - 300, now);
    Test.assertEqualMessage(true, exact[0], "position at ten minutes usable");
    Test.assertEqualMessage(false, exact[1], "exactly 300 seconds is recent");
    Test.assertEqualMessage(false, exact[2], "recent good fix needs no acquisition");
    var almost = NearbyLocationPolicy.decide(Position.QUALITY_GOOD, now - 299, now);
    Test.assertEqualMessage(false, almost[1], "299 seconds recent");
    var old = NearbyLocationPolicy.decide(Position.QUALITY_GOOD, now - 301, now);
    Test.assertEqualMessage(true, old[1], "301 seconds stale");
    Test.assertEqualMessage(true, old[2], "acquire new fix");
    var ancient = NearbyLocationPolicy.decide(Position.QUALITY_LAST_KNOWN, 1, now);
    Test.assertEqualMessage(true, ancient[0], "no hard age cap");
    Test.assertEqualMessage(true, ancient[1], "very old position marked stale");
    var unknown = NearbyLocationPolicy.decide(Position.QUALITY_USABLE, null, now);
    Test.assertEqualMessage(true, unknown[0], "missing timestamp still usable");
    Test.assertEqualMessage(true, unknown[1], "unknown age marked stale");
    Test.assertEqualMessage(true, unknown[2], "unknown age requests fix");
    var skew = NearbyLocationPolicy.decide(Position.QUALITY_GOOD, now + 1, now);
    Test.assertEqualMessage(false, skew[1], "negative age is recent");
    var lastKnown = NearbyLocationPolicy.decide(Position.QUALITY_LAST_KNOWN, now, now);
    Test.assertEqualMessage(true, lastKnown[1], "last-known quality always stale");
    Test.assertEqualMessage(false, NearbyLocationPolicy.decide(
        Position.QUALITY_NOT_AVAILABLE, now, now)[0], "unavailable not usable");
    Test.assertEqualMessage(true, NearbyLocationPolicy.decide(
        Position.QUALITY_NOT_AVAILABLE, now, now)[1], "unavailable quality is stale");
    Test.assertEqualMessage(true, lastKnown[2], "last-known quality still needs fix");
    var poor = NearbyLocationPolicy.decide(Position.QUALITY_POOR, now, now);
    Test.assertEqualMessage(false, poor[2], "recent poor quality is enough");
    Test.assertEqualMessage(false, NearbyLocationPolicy.decide(Position.QUALITY_USABLE, now, now)[2],
        "recent usable quality is enough");
    return true;
}

(:test, :nearby)
function testNearbyFixIndicatorPlacement(logger as Logger) as Boolean {
    // Every nearby-capable product from manifest.xml, matched to its SDK
    // simulator.json display. All 24 currently have round screens.
    var profiles = [
        ["descentmk1", 240, 240], ["descentmk2", 280, 280],
        ["descentmk2s", 240, 240], ["descentmk343mm", 390, 390],
        ["descentmk351mm", 454, 454], ["fenix5plus", 240, 240],
        ["fenix5splus", 240, 240], ["fenix5x", 240, 240],
        ["fenix5xplus", 240, 240], ["fenix6pro", 260, 260],
        ["fenix6spro", 240, 240], ["fenix6xpro", 280, 280],
        ["fr645m", 240, 240], ["fr745", 240, 240],
        ["fr945", 240, 240], ["fr945lte", 240, 240],
        ["marqadventurer", 240, 240], ["marqathlete", 240, 240],
        ["marqaviator", 240, 240], ["marqcaptain", 240, 240],
        ["marqcommander", 240, 240], ["marqdriver", 240, 240],
        ["marqexpedition", 240, 240], ["marqgolfer", 240, 240]
    ];
    Test.assertEqualMessage(24, profiles.size(), "all nearby-capable manifest products");
    for (var i = 0; i < profiles.size(); i++) {
        var profile = profiles[i] as Array;
        var width = profile[1] as Number;
        var height = profile[2] as Number;
        var titleTop = height / 6;
        for (var state = 0; state < 3; state++) {
            var gps = state != 1;
            var network = state != 0;
            var bounds = NearbyFixIndicator.rect(width, height, titleTop, true, gps, network);
            Test.assertMessage(bounds != null, profile[0] + " fits every icon state");
            var x = (bounds as Array)[0] as Number;
            var y = (bounds as Array)[1] as Number;
            var size = (bounds as Array)[2] as Number;
            var networkX = (bounds as Array)[3] as Number;
            var networkY = (bounds as Array)[4] as Number;
            var radius = width / 2 - 5;
            if (gps) {
                Test.assertMessage(size >= 16 && size >= width * 9 / 100,
                    profile[0] + " GPS icon is large enough");
                Test.assertMessage(y >= 0 &&
                    y + size + NearbyFixIndicator.TITLE_GAP <= titleTop,
                    profile[0] + " GPS clear of both title rectangles");
                var side = width / 2 - x;
                var top = height / 2 - y;
                Test.assertMessage(top * top + side * side <= radius * radius,
                    profile[0] + " GPS top outer corner inside circle");
                if (!network) {
                    Test.assertMessage(nearbyIndicatorWithinOne(x * 2 + size, width),
                        profile[0] + " single GPS icon centred");
                }
            }
            if (network) {
                Test.assertMessage(networkY >= 0 &&
                    networkY + NearbyFixIndicator.NETWORK_SIZE +
                        NearbyFixIndicator.TITLE_GAP <= titleTop,
                    profile[0] + " network clear of both title rectangles");
                var side = networkX + NearbyFixIndicator.NETWORK_SIZE - width / 2;
                var top = height / 2 - networkY;
                Test.assertMessage(top * top + side * side <= radius * radius,
                    profile[0] + " network top outer corner inside circle");
                if (!gps) {
                    Test.assertMessage(nearbyIndicatorWithinOne(networkX * 2 +
                        NearbyFixIndicator.NETWORK_SIZE, width),
                        profile[0] + " single network icon centred");
                }
            }
            if (gps && network) {
                Test.assertMessage(NearbyFixIndicator.GPS_FIRST,
                    "declared order puts GPS on left");
                Test.assertEqualMessage(x + size + NearbyFixIndicator.NETWORK_GAP,
                    networkX, "pair has exactly the declared gap and order");
                Test.assertMessage(nearbyIndicatorWithinOne(x,
                    width - networkX - NearbyFixIndicator.NETWORK_SIZE),
                    profile[0] + " pair has equal outer margins");
                Test.assertMessage(nearbyIndicatorWithinOne(y * 2 + size,
                    networkY * 2 + NearbyFixIndicator.NETWORK_SIZE),
                    profile[0] + " both icons share a vertical centre");
            }
        }
        var favouriteTitle = height / 10 + NearbyFixIndicator.NETWORK_TITLE_SHIFT;
        var lone = NearbyFixIndicator.rect(width, height, favouriteTitle,
            true, false, true) as Array;
        Test.assertMessage(lone != null, profile[0] + " network-only favourite fits");
        var bitmapY = lone[4] as Number;
        var bitmapX = lone[3] as Number;
        var left = width / 2 - bitmapX;
        var top = height / 2 - bitmapY;
        var radius = width / 2 - 5;
        Test.assertMessage(top * top + left * left <= radius * radius,
            profile[0] + " network-only favourite inside bezel");
        Test.assertMessage(bitmapY + NearbyFixIndicator.NETWORK_SIZE +
            NearbyFixIndicator.TITLE_GAP <= favouriteTitle,
            profile[0] + " network-only favourite clears title");
    }
    var mk1 = NearbyFixIndicator.rect(240, 240, 40, true, true, true) as Array;
    Test.assertEqualMessage(96, mk1[0], "Mk1 paired GPS left");
    Test.assertEqualMessage(14, mk1[1], "Mk1 paired icon top");
    Test.assertEqualMessage(24, mk1[2], "Mk1 icon diameter");
    Test.assertEqualMessage(124, mk1[3], "Mk1 network on right");
    Test.assertEqualMessage(16, mk1[4], "network bitmap centres at GPS centre");
    Test.assertMessage(NearbyFixIndicator.rect(176, 176, 176 / 6, true, true, true) == null,
        "skip paired icons when the top chord is too narrow");
    var rectangle = NearbyFixIndicator.rect(160, 240, 40, false, true, false) as Array;
    Test.assertEqualMessage(16, rectangle[2], "minimum diameter on a narrow rectangle");
    Test.assertMessage(rectangle[1] + rectangle[2] < 40,
        "rectangular screen title remains unobstructed");
    var loneNetwork = NearbyFixIndicator.rect(240, 240,
        240 / 10 + NearbyFixIndicator.NETWORK_TITLE_SHIFT,
        true, false, true) as Array;
    Test.assertEqualMessage(6, loneNetwork[4], "network-only favourite clears bezel");
    Test.assertMessage((loneNetwork[4] as Number) + NearbyFixIndicator.NETWORK_SIZE +
        NearbyFixIndicator.TITLE_GAP <=
        240 / 10 + NearbyFixIndicator.NETWORK_TITLE_SHIFT,
        "network-only favourite icon clears its shifted title");
    Test.assertMessage(NearbyFixIndicator.rect(240, 240, 40, true, false, false) == null,
        "no icon when neither warning applies");
    return true;
}

// A real Dc on the oldest nearby-capable profile catches SDK symbols that
// compile but are missing in the simulator, unlike pure layout assertions.
(:test, :nearby)
function testNearbyIndicatorDrawingOnDevice(logger as Logger) as Boolean {
    Test.assertMessage(Graphics has :BufferedBitmap,
        "this profile must provide a drawing surface, not silently skip");
    var bitmap = new Graphics.BufferedBitmap({:width => 48, :height => 40});
    Test.assertMessage(bitmap has :getDc, "buffer has drawing context");
    var dc = bitmap.getDc();
    Test.assertMessage(dc has :fillCircle && dc has :fillRectangle &&
        dc has :drawLine && dc has :setPenWidth && dc has :setColor &&
        dc has :drawBitmap, "production Dc primitives must exist at runtime");
    Test.assertMessage(WatchUi has :loadResource, "network bitmap loader exists");
    Test.assertEqualMessage(48, dc.getWidth(), "test drawing width");
    Test.assertEqualMessage(40, dc.getHeight(), "test drawing height");
    dc.setColor(Constants.COLOUR_FOREGROUND, Constants.COLOUR_BACKGROUND);
    dc.clear();
    var bounds = NearbyFixIndicator.rect(48, 40, 32, false, true, true) as Array<Number>;
    Test.assertMessage(bounds != null, "both icons fit the test drawing surface");
    Test.assertEqualMessage(4, bounds[0], "GPS inside the tiny test surface");
    Test.assertEqualMessage(24, bounds[3], "network bitmap clear of GPS");
    NearbyFixIndicator.draw(dc, bounds);
    var networkIcon = WatchUi.loadResource(Rez.Drawables.ConnectionProblemIcon)
        as BitmapReference;
    dc.drawBitmap(bounds[3], bounds[4], networkIcon);
    return true;
}
