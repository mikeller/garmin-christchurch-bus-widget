import Toybox.Lang;

// Compare the immutable compressed visits by content, not Array identity.
class DepartureRowsKey {
    static function same(a as Array?, b as Array?, widthA as Number, widthB as Number,
                         heightA as Number, heightB as Number) as Boolean {
        if (widthA != widthB || heightA != heightB) {
            return false;
        }
        if (a == null || b == null) {
            return a == null && b == null;
        }
        if (a.size() != b.size()) {
            return false;
        }
        for (var i = 0; i < a.size(); i++) {
            var left = a[i] as Dictionary;
            var right = b[i] as Dictionary;
            if (!sameField(left["ExpectedDepartureTime"], right["ExpectedDepartureTime"]) ||
                !sameField(left["PublishedLineName"], right["PublishedLineName"]) ||
                !sameField(left["DestinationName"], right["DestinationName"]) ||
                !sameField(left["VehicleAtStop"], right["VehicleAtStop"])) {
                return false;
            }
        }
        return true;
    }

    private static function sameField(a as Object?, b as Object?) as Boolean {
        if (a == null || b == null) {
            return a == null && b == null;
        }
        return a.equals(b);
    }
}
