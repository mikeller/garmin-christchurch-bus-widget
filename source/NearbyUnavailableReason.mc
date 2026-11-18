import Toybox.Lang;
import Toybox.WatchUi;

(:nearby)
class NearbyUnavailableReason {
    static const NO_FIX = 0;
    static const LOCATION_ERROR = 1;
    static const TILE_CODE = 2;
    static const BAD_TILE = 3;

    static function forTile(responseCode as Number, valid as Boolean) as Number {
        return responseCode == 200 && !valid ? BAD_TILE : TILE_CODE;
    }

    static function hint(reason as Number, code as Number) as String {
        if (reason == LOCATION_ERROR) {
            return WatchUi.loadResource(Rez.Strings.NearbyLocationErrorHint) as String;
        }
        if (reason == NO_FIX) {
            return WatchUi.loadResource(Rez.Strings.NearbyNoFixHint) as String;
        }
        if (reason == BAD_TILE) {
            return WatchUi.loadResource(Rez.Strings.NearbyBadTileHint) as String;
        }
        return (WatchUi.loadResource(Rez.Strings.NearbyTileCodeHint) as String) + code;
    }
}
