import Toybox.Lang;
import Toybox.Math;
import Toybox.Application;
import Toybox.Application.Properties;

(:glance)
class ChristchurchBusAppProperties {
    private static var stops as Array<Dictionary>?;

    static function loadStops() as Array<Dictionary> {
        if (stops == null) {
            stops = Properties.getValue("stops") as Array<Dictionary>?;           
        }

        return stops != null ? stops : [];
    }

    static function saveStops(localStops as Array<Dictionary>, needsUpdate as Boolean) as Void {
        if (needsUpdate) {
            stops = localStops;
            Properties.setValue("stops", stops as Array<PropertyValueType>);
        }
    }

    static function getStopsProperty() as Array<Dictionary>? {    
        var localStops = loadStops();
        var needsUpdate = false;
        var i = 0;
        while (i < localStops.size()) {
            var stop = localStops[i];
            var stopId = stop["stopId"] as Number;

            var j;
            for (j = 0; j < i; j++) {
                var firstStopId = localStops[j]["stopId"] as Number;

                if (stopId == firstStopId) {
                    localStops.remove(stop);
                    needsUpdate = true;

                    Utils.log("Duplicate location removed: " + stop.toString());

                    break;
                }
            }

            if (j == i) {
                i++;
            }
        }

        saveStops(localStops, needsUpdate);
 
        return localStops;
    }

    static function setStopNameIfEmpty(stopId as Number, stopName as String) as Void {
        var localStops = loadStops();

        var needsUpdate = false;
        var i = 0;
        while (i < localStops.size()) {
            var stop = localStops[i];
            var currentStopId = stop["stopId"] as Number;
            var currentStopName = stop["displayName"] as String;

            if (currentStopId == stopId && "".equals(currentStopName)) {
                stop["displayName"] = stopName;
                localStops[i] = stop;
                needsUpdate = true;
            }

            i++;
        }

        saveStops(localStops, needsUpdate);      
    }

    static function getCustomUrl() as String? {
        var customUrl = Properties.getValue("customUrl") as String;
        if ("".equals(customUrl)) {
            customUrl = null;
        }

        return customUrl;
    }
}
