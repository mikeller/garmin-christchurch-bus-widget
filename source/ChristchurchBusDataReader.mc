import Toybox.Lang;
import Toybox.Application;
import Toybox.System;
import Toybox.Communications;

class ChristchurchBusDataReader {
    private const DATA_PATH as String = "rti/siri/v1/sm";

    private const NEAR as String = " near ";
    private const BUS as String =  "Bus ";
    private const PLATFORM as String =  " (Platform ";

    private var baseUrl as String = "https://apis.metroinfo.co.nz/";

    private var connectionProblem as Boolean = false;

    private var concurrentRequestCount as Number = 0;
    private var requestIsRunning as Dictionary<Number, Boolean> = {} as Dictionary<Number, Boolean>;

    function initialize() {
        var customUrl = ChristchurchBusAppProperties.getCustomUrl();
        if (customUrl != null) {
            baseUrl = customUrl;
        }
    }

    function getBusData(stopId as Number, handle as Number, callback as Method(data as Dictionary<String, String or Array>?, handle as Number, requestIsCompleted as Boolean, dataIsStale as Boolean) as Void) as Boolean {
        if (concurrentRequestCount >= Constants.MAX_CONCURRENT_REQUESTS) {
            Utils.log("Concurrent request limit reached for handle: " + handle);

            return false;
        } else {
            concurrentRequestCount++;
        }

        var cache = ChristchurchBusDataCache.tryGetCachedData(stopId, false);
        if (cache != null) {
            callback.invoke(cache as Dictionary<String, String or Array>, handle, true, false);

            concurrentRequestCount--;
            return true;
        }

        var existingConnectionProblem = connectionProblem;
        if (existingConnectionProblem) {
            showStaleData(stopId, handle, false, callback);
        }

        if (requestIsRunning[handle]) {
            Utils.log("Request already running for handle: " + handle);

            concurrentRequestCount--;
            return true;
        }

        var params = {
            "stopcode" => stopId,
        };

        var headers = {
            "Ocp-Apim-Subscription-Key" => WatchUi.loadResource(Rez.Strings.SubscriptionKey) as String,
        };

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => headers,
            :context => {
                "callback" => callback,
                "stopId" => stopId,
                "handle" => handle,
                "existingConnectionProblem" => existingConnectionProblem,
            },
        };

        if (System.getDeviceSettings().connectionAvailable) {
            requestIsRunning[handle] = true;

            Communications.makeWebRequest(baseUrl + DATA_PATH, params, options, method(:onReceiveData));

            Utils.log("Sent request for handle: " + handle + ", " + stopId);
        } else {
            connectionProblem = true;

            showStaleData(stopId, handle, true, callback);

            Utils.log("No connection for request: handle: " + handle + ", " + stopId);

            concurrentRequestCount--;
        }

        return true;
    }

    private function persistStopName(stopId as Number, data as Dictionary<String, String or Array>) as Void {
        var visits = data["MonitoredStopVisit"] as Array<Dictionary>?;
        if (visits != null) {
            var visit = visits[0];
            var journey = visit["MonitoredVehicleJourney"] as Dictionary<String, String or Number or Boolean or Dictionary>;
            var stopName = (journey["MonitoredCall"] as Dictionary<String, String or Boolean or Dictionary>)["StopPointName"] as String;
            
            var pos = stopName.find(NEAR);
            if (pos != null) {
                stopName = stopName.substring(0, pos) as String;
            }

            pos = stopName.find(BUS);
            if (pos != null) {
                stopName = stopName.substring(0, pos) + stopName.substring(pos + BUS.length(), stopName.length());
            }
            
            pos = stopName.find(PLATFORM);
            if (pos != null) {
                stopName = stopName.substring(0, pos + 2) + stopName.substring(pos + PLATFORM.length(), stopName.length());
            }

            ChristchurchBusAppProperties.setStopNameIfEmpty(stopId, stopName);
        }
    }

    function compressData(data as Dictionary<String, String or Array>) as Dictionary<String, String or Array> {
        var compressedData = {
            "ValidUntil" => data["ValidUntil"],
            "ErrorCondition" => data["ErrorCondition"],
        } as Dictionary<String, String or Array>;

        var visits = data["MonitoredStopVisit"] as Array<Dictionary>?;
        if (visits != null) {
            var index = 0;
            var compressedVisits = [];
            while (index < visits.size()) {
                var visit = visits[index];
                var journey = visit["MonitoredVehicleJourney"] as Dictionary<String, String or Number or Boolean or Dictionary>;
                var call = (journey["MonitoredCall"] as Dictionary<String, String or Number or Boolean or Dictionary>);
                var expectedDepartureTimeString = call["ExpectedDepartureTime"] as String;

                var compressedVisit = {
                    "ExpectedDepartureTime" => expectedDepartureTimeString,
                    "VehicleAtStop" => call["VehicleAtStop"],
                    "PublishedLineName" => journey["PublishedLineName"],
                    "DestinationName" => journey["DestinationName"],
                };

                compressedVisits.add(compressedVisit);

                index++;
            }

            compressedData["MonitoredStopVisit"] = compressedVisits;
        }

        compressedData["ErrorCondition"] = data["ErrorCondition"];

        return compressedData;
    }

    function onReceiveData(responseCode as Number, data as Dictionary?, context as Dictionary<String, String or Method or Number or Boolean>) as Void {
        var callback = context["callback"] as Method(data as Dictionary<String, String or Array>?, handle as Number, requestIsCompleted as Boolean, dataIsStale as Boolean) as Void;
        var handle = context["handle"] as Number;
        var stopId = context["stopId"] as Number;

        var done = false;
        if (responseCode >= 200 && responseCode < 300 && data != null) {
            try {
                var deliveries = ((data["Siri"] as Dictionary<String, Dictionary>)["ServiceDelivery"] as Dictionary<String, String or Dictionary or Array>)["StopMonitoringDelivery"] as Array<Dictionary>;
                var delivery = {} as Dictionary<String, String or Array>;
                if (deliveries.size() > 0) {
                    delivery = deliveries[0] as Dictionary<String, String or Array>;

                    persistStopName(stopId, delivery);
                }

                var compressedData = compressData(delivery);

                ChristchurchBusDataCache.setCachedData(stopId, compressedData);

                connectionProblem = false;

                Utils.log("Received data for handle: " + handle + ", " + stopId);

                callback.invoke(compressedData, handle, true, false);

                done = true;
            } catch (exception instanceof UnexpectedTypeException) {
                Utils.log("Received data format problem for handle: " + handle + ", " + exception.getErrorMessage());
                exception.printStackTrace();
            }
        } else {
            Utils.log("Received data nok for handle: " + handle + ", " + responseCode);
        }

        if (!done) {
            connectionProblem = true;

            if (!(context["existingConnectionProblem"] as Boolean)) {
                showStaleData(stopId, handle, true, callback);
            }
        }

        requestIsRunning[handle] = false;
        concurrentRequestCount--;
    }

    private function showStaleData(stopId as Number, handle as Number, requestIsCompleted as Boolean, callback as Method(data as Dictionary<String, String or Array>?, handle as Number, requestIsCompleted as Boolean, dataIsStale as Boolean) as Void) as Void {
        var cache = ChristchurchBusDataCache.tryGetCachedData(stopId, true);
        callback.invoke(cache, handle, requestIsCompleted, true);
    }
}
