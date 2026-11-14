import Toybox.Application.Properties;
import Toybox.Lang;

(:nearby)
class NearbyAvailability {
    static function enabled() as Boolean {
        return Properties.getValue("nearbyEnabled") as Boolean;
    }

    static function favouritesBeforeNearby() as Number {
        return Properties.getValue("favouritesBeforeNearby") as Number;
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
