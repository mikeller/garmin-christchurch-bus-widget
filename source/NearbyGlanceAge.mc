import Toybox.Lang;

(:glance, :nearby)
class NearbyGlanceAge {
    static function label(at as Number, now as Number) as String {
        if (at == 0) {
            return " age unknown";
        }
        var minutes = now >= at ? (now - at) / 60 : 0;
        if (minutes < 60) {
            return " " + minutes + "m old";
        }
        return " " + (minutes / 60) + "h old";
    }
}

(:glance, :noNearby)
class NearbyGlanceAge {
    static function label(at as Number, now as Number) as String {
        return "";
    }
}
