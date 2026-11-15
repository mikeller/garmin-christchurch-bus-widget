import Toybox.Lang;

class NearbyPageNames {
    static function clean(name as String) as String {
        var pos = name.find(" near ");
        if (pos != null) {
            name = name.substring(0, pos);
        }
        pos = name.find("Bus ");
        if (pos != null) {
            name = name.substring(0, pos) + name.substring(pos + 4, name.length());
        }
        pos = name.find(" (Platform ");
        if (pos != null) {
            name = name.substring(0, pos + 2) + name.substring(pos + 11, name.length());
        }
        return name;
    }

    (:nearby)
    static function displayName(entry as Array, nearby as Array) as String {
        var raw = entry[NearbyStopMaths.ENTRY_NAME] as String;
        var cleanName = clean(raw);
        for (var i = 0; i < nearby.size(); i++) {
            var other = nearby[i] as Array;
            if (other[NearbyStopMaths.ENTRY_CODE] != entry[NearbyStopMaths.ENTRY_CODE] &&
                cleanName.equals(clean(other[NearbyStopMaths.ENTRY_NAME] as String))) {
                return raw;
            }
        }
        return cleanName;
    }

    (:nearby)
    static function distance(metres as Number) as String {
        if (metres < 1000) {
            return metres.toString() + " m";
        }
        // Round to the nearest 100 m, half up. Keep one decimal at 3 km too.
        var tenths = (metres + 50) / 100;
        return (tenths / 10).toString() + "." + (tenths % 10).toString() + " km";
    }
}
