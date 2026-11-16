import Toybox.Lang;
import Toybox.Test;

(:test, :nearby)
function testNearbyUnavailableReasons(logger as Logger) as Boolean {
    Test.assertEqualMessage(NearbyUnavailableReason.BAD_TILE,
        NearbyUnavailableReason.forTile(200, false), "malformed 200");
    Test.assertEqualMessage(NearbyUnavailableReason.TILE_CODE,
        NearbyUnavailableReason.forTile(-300, false), "timeout code");
    Test.assertEqualMessage(NearbyUnavailableReason.TILE_CODE,
        NearbyUnavailableReason.forTile(-400, false), "404 mapping");
    Test.assertEqualMessage(NearbyUnavailableReason.TILE_CODE,
        NearbyUnavailableReason.forTile(503, false), "HTTP status");
    return true;
}
