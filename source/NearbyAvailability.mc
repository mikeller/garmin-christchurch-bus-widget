import Toybox.Application.Properties;
import Toybox.Lang;

(:nearby)
class NearbyAvailability {
    static const DEFAULT_STOPS_TO_SHOW = 3;

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

    static function stopsToShow() as Number {
        try {
            return normaliseStopsToShow(Properties.getValue("nearbyStopsToShow"));
        } catch (e) {
            return DEFAULT_STOPS_TO_SHOW;
        }
    }

    static function normaliseStopsToShow(value as Object?) as Number {
        // Invalid values use the default, never clamp. Keep the tile-contract
        // maximum in NearbyStopMaths.NEARBY_COUNT when changing this range.
        if (value instanceof Number && value >= 1 && value <= NearbyStopMaths.NEARBY_COUNT) {
            return value;
        }
        return DEFAULT_STOPS_TO_SHOW;
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
