import Toybox.Lang;
import Toybox.Math;
import Toybox.Application;
import Toybox.Application.Properties;

(:glance)
class ChristchurchBusAppProperties {
    static function getStopsProperty() as Array<Dictionary>? {
        var stops = Properties.getValue("stops") as Array<Dictionary>?;

        if (stops != null) {
            var needsUpdate = false;
            var i = 0;
            while (i < stops.size()) {
                var stop = stops[i];
                var stopId = stop["stopId"] as Number;

                var j;
                for (j = 0; j < i; j++) {
                    var firstStopId = stops[j]["stopId"] as Number;

                    if (stopId == firstStopId) {
                        stops.remove(stop);
                        needsUpdate = true;

                        Utils.log("Duplicate location removed: " + stop.toString());

                        break;
                    }
                }

                if (j == i) {
                    i++;
                }
            }

            if (needsUpdate) {
                Properties.setValue("stops", stops as Array<PropertyValueType>);
            }
        }

        return stops;
    }

    static function getCustomUrl() as String? {
        var customUrl = Properties.getValue("customUrl") as String;
        if ("".equals(customUrl)) {
            customUrl = null;
        }

        return customUrl;
    }
}
