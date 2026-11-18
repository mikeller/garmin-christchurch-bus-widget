import Toybox.Lang;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.System;

// Diagnostic marker exists only in debug builds. LastStop's release format
// and the favourite-only product rule are unchanged.
(:debug, :nearby)
class NearbyLastStopTrace {
    private static const KEY = "LastStopTrace";

    static function cleared() as Void {
        try {
            Storage.setValue(KEY, "cleared-by-nearby");
        } catch (e) {}
    }

    static function favourite() as Void {
        try {
            Storage.deleteValue(KEY);
        } catch (e) {}
    }

    static function restore(value as Object?, favourites as Array<Dictionary>,
                            setting as Number, now as Number) as Void {
        var reason = NearbyFavouriteMemory.restoreReason(value, favourites, setting, now);
        var text = "invalid";
        if (reason == NearbyFavouriteMemory.RESTORED) {
            text = "restored";
        } else if (reason == NearbyFavouriteMemory.EXPIRED) {
            text = "expired";
        } else if (reason == NearbyFavouriteMemory.NO_RECORD) {
            text = "no-record";
            try {
                if ("cleared-by-nearby".equals(Storage.getValue(KEY))) {
                    text = "cleared-by-nearby";
                }
            } catch (e) {}
        } else if (reason == NearbyFavouriteMemory.OUT_OF_RANGE) {
            text = "out-of-range";
        } else if (reason == NearbyFavouriteMemory.DISABLED) {
            text = "disabled";
        }
        System.println("LastStop restore: " + text);
    }
}

(:release, :nearby)
class NearbyLastStopTrace {
    static function cleared() as Void {}
    static function favourite() as Void {}
    static function restore(value as Object?, favourites as Array<Dictionary>,
                            setting as Number, now as Number) as Void {}
}
