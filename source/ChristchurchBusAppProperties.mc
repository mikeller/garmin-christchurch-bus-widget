import Toybox.Lang;
import Toybox.Math;
import Toybox.Application;
import Toybox.Application.Properties;

(:glance)
class ChristchurchBusAppProperties {
    private static var stops as Array<Dictionary>?;
    private static var canWriteStops as Boolean = true;

    static function loadStops() as Array<Dictionary> {
        if (stops == null) {
            var stored = Properties.getValue("stops");
            stops = StoredBusData.normaliseStops(stored);
            // No later duplicate/name write may persist a filtered array.
            canWriteStops = stored instanceof Array &&
                (stored as Array).size() == (stops as Array).size();
        }

        return stops != null ? stops : [];
    }

    static function saveStops(localStops as Array<Dictionary>, needsUpdate as Boolean) as Void {
        if (needsUpdate && canWriteStops && localStops.size() > 0) {
            stops = localStops;
            Properties.setValue("stops", stops as Array<PropertyValueType>);
        }
    }

    (:debug)
    static function resetStopsForTest() as Void {
        stops = null;
        canWriteStops = true;
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
                stop["displayName"] = stopName.length() > 32 ?
                    stopName.substring(0, 32) : stopName;
                localStops[i] = stop;
                needsUpdate = true;
            }

            i++;
        }

        saveStops(localStops, needsUpdate);
    }

    static function getStopResetTimeMin() as Number {
        return Properties.getValue("stopResetTimeMin") as Number;
    }

    static function getCustomUrl() as String? {
        var customUrl = Properties.getValue("customUrl") as String;
        if ("".equals(customUrl)) {
            customUrl = null;
        }

        return customUrl;
    }

    (:nearby)
    static function getCustomTilesUrl() as String? {
        var url = Properties.getValue("customTilesUrl") as String?;
        return url == null || "".equals(url) ? null : url;
    }

    (:nearby)
    static function nearbyEnabled() as Boolean {
        // This accessor is also used by the glance. NearbyAvailability is
        // widget-only, so read the same setting without crossing that scope.
        return Properties.getValue("nearbyEnabled") as Boolean;
    }

    (:noNearby)
    static function nearbyEnabled() as Boolean {
        return false;
    }

    static function favouritesBeforeNearby() as Number {
        return NearbyAvailability.favouritesBeforeNearby();
    }

    (:nearby)
    static function nearbyStopsToShow() as Number {
        return NearbyAvailability.stopsToShow();
    }
}
