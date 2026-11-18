import Toybox.Lang;
import Toybox.Math;
import Toybox.Application;
import Toybox.Application.Properties;

(:glance)
class ChristchurchBusAppProperties {
    private static var stops as Array<Dictionary>?;

    static function loadStops() as Array<Dictionary> {
        if (stops == null) {
            var stored = Properties.getValue("stops");
            var clean = [] as Array<Dictionary>;
            if (stored instanceof Array) {
                var list = stored as Array;
                for (var i = 0; i < list.size(); i++) {
                    if (StoredBusData.validStop(list[i])) {
                        clean.add(list[i] as Dictionary);
                    }
                }
            }
            stops = clean;
            // Repair invalid persisted entries once, so relaunching the
            // widget cannot repeat the same crash.
            if (stored != null && (!(stored instanceof Array) ||
                (stored as Array).size() != clean.size())) {
                try {
                    Properties.setValue("stops", clean as Array<PropertyValueType>);
                } catch (e) {
                    // The validated in-memory list is still safe this session.
                }
            }
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
