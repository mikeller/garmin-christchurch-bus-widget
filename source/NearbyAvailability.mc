import Toybox.Application.Properties;
import Toybox.Lang;

(:nearby)
class NearbyAvailability {
    static function enabled() as Boolean {
        return Properties.getValue("nearbyEnabled") as Boolean;
    }

    static function favouritesBeforeNearby() as Number {
        try {
            return normaliseFavouritesBeforeNearby(Properties.getValue("favouritesBeforeNearby"));
        } catch (e) {
            // A missing setting on an older installation also means nearby first.
            return 0;
        }
    }

    static function normaliseFavouritesBeforeNearby(value as Object?) as Number {
        // Blank, corrupt or out-of-range values all use the configured default.
        if (value instanceof Number && value >= 0 && value <= 16) {
            return value;
        }
        return 0;
    }
}

(:noNearby)
class NearbyAvailability {
    static function enabled() as Boolean {
        return false;
    }

    static function favouritesBeforeNearby() as Number {
        return 0;
    }
}
