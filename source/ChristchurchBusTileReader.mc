import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// A single outstanding tile per reader. The callback receives (result, stops,
// stale); stops are borrowed from the parsed tile and should be reduced to the
// nearest entries by the caller, rather than retained in long-lived memory.
(:nearby)
class ChristchurchBusTileReader {
    static const READY = 0;
    static const NO_STOPS = 1;
    static const OFFLINE = 2;
    static const UNAVAILABLE = 3;
    static const DEFAULT_URL = "https://mikeller.github.io/garmin-christchurch-bus-widget";
    static const TTL_SECONDS = 259200; // three days
    private static const INDEX_KEY = "nearby:tiles";

    private var pendingKey as String?;
    private var pendingCallback as Method?;
    private var indexKey as String = INDEX_KEY;

    (:debug)
    function useTestIndex() as Void {
        indexKey = "nearby:test-index";
    }

    function isPending() as Boolean {
        return pendingKey != null;
    }

    // JSON responseType produces a Dictionary for an object root. Reject
    // malformed data before it can reach the distance maths or persistent cache.
    static function validTile(body as Object?) as Boolean {
        if (!(body instanceof Dictionary)) {
            return false;
        }
        var tile = body as Dictionary;
        var generation = tile["g"];
        var stops = tile["s"];
        if (!(tile["v"] instanceof Number) || tile["v"] != 1 ||
            !(generation instanceof String) || (generation as String).length() != 10 ||
            !"-".equals((generation as String).substring(4, 5)) ||
            !"-".equals((generation as String).substring(7, 8)) || !(stops instanceof Array)) {
            return false;
        }
        var date = generation as String;
        for (var i = 0; i < date.length(); i++) {
            if (i != 4 && i != 7 && "0123456789".find(date.substring(i, i + 1)) == null) {
                return false;
            }
        }
        var month = date.substring(5, 7).toNumber();
        var day = date.substring(8, 10).toNumber();
        if (month < 1 || month > 12 || day < 1 || day > 31) {
            return false;
        }
        var list = stops as Array;
        for (var i = 0; i < list.size(); i++) {
            var stop = list[i];
            if (!(stop instanceof Array) || (stop as Array).size() != 4) {
                return false;
            }
            var row = stop as Array;
            if (!(row[0] instanceof Number) || (row[0] as Number) < 1000 ||
                (row[0] as Number) > 99999 || !(row[1] instanceof Number) ||
                !(row[2] instanceof Number) || !(row[3] instanceof String)) {
                return false;
            }
        }
        return true;
    }

    static function resultFor(responseCode as Number, body as Object?) as Number {
        if (responseCode == -400) {
            return NO_STOPS;
        }
        if (responseCode == -104) {
            return OFFLINE;
        }
        return responseCode == 200 && validTile(body) ? READY : UNAVAILABLE;
    }

    // Returns false only when another request is pending or all HTTP slots
    // are occupied; no callback is invoked in that case.
    function getTile(ty as Number, tx as Number, callback as Method) as Boolean {
        if (pendingKey != null) {
            return false;
        }
        var key = ty.toString() + "," + tx.toString();
        var cached = readCache(key, false);
        if (cached != null) {
            callback.invoke(READY, cached["s"] as Array, false);
            return true;
        }
        if (!System.getDeviceSettings().connectionAvailable) {
            deliverOffline(key, callback);
            return true;
        }
        if (!NearbyRequestSlots.acquire()) {
            return false;
        }
        pendingKey = key;
        pendingCallback = callback;
        var base = ChristchurchBusAppProperties.getCustomTilesUrl();
        if (base == null) {
            base = DEFAULT_URL;
        }
        // Both a bare base and one ending in '/' form the same URL.
        if ((base as String).length() > 0 && "/".equals((base as String).substring((base as String).length() - 1, (base as String).length()))) {
            base = (base as String).substring(0, (base as String).length() - 1);
        }
        try {
            Communications.makeWebRequest((base as String) + "/t/" + ty + "/" + tx + ".json",
                null, { :method => Communications.HTTP_REQUEST_METHOD_GET,
                        :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON },
                method(:onReceiveTile));
        } catch (e) {
            pendingKey = null;
            pendingCallback = null;
            NearbyRequestSlots.release();
            callback.invoke(UNAVAILABLE, null, false);
        }
        return true;
    }

    // No context argument: older devices may call this synchronously with
    // precisely two arguments when the BLE connection drops.
    function onReceiveTile(responseCode as Number, body as Communications.ContentType?) as Void {
        var key = pendingKey;
        var callback = pendingCallback;
        pendingKey = null;
        pendingCallback = null;
        if (key == null || callback == null) {
            return;
        }
        NearbyRequestSlots.release();
        var result = resultFor(responseCode, body);
        if (result == READY) {
            var tile = body as Dictionary;
            writeCache(key as String, tile);
            callback.invoke(READY, tile["s"] as Array, false);
        } else if (result == OFFLINE) {
            deliverOffline(key as String, callback as Method);
        } else {
            callback.invoke(result, null, false);
        }
    }

    private function deliverOffline(key as String, callback as Method) as Void {
        var stale = readCache(key, true);
        if (stale != null) {
            callback.invoke(READY, stale["s"] as Array, true);
        } else {
            callback.invoke(OFFLINE, null, false);
        }
    }

    function readCache(key as String, allowExpired as Boolean) as Dictionary? {
        try {
            var entry = Storage.getValue("nearby:" + key);
            if (!(entry instanceof Dictionary)) {
                return null;
            }
            var data = entry as Dictionary;
            var fetched = data["at"];
            var tile = data["tile"];
            if (!(fetched instanceof Number) || !validTile(tile) ||
                !(data["g"] instanceof String) ||
                !((data["g"] as String).equals((tile as Dictionary)["g"]))) {
                Storage.deleteValue("nearby:" + key);
                return null;
            }
            if (!allowExpired && (Time.now().value() - (fetched as Number) >= TTL_SECONDS ||
                                   Time.now().value() < (fetched as Number))) {
                return null;
            }
            return tile as Dictionary;
        } catch (e) {
            return null;
        }
    }

    function writeCache(key as String, tile as Dictionary) as Void {
        // The documented per-value cap is 32 KB; actual object-store capacity
        // varies by device. A tile is <= 4096 UTF-8 bytes on the wire, but
        // parsed objects have overhead. A failed write must not lose the tile
        // just fetched or affect live departures.
        var storageKey = "nearby:" + key;
        try {
            var old = Storage.getValue(indexKey);
            var previous = old instanceof Array ? old as Array : [] as Array;
            var keys = [] as Array;
            // Index order is oldest to newest. Retain the most recently used
            // previous tile, not the oldest one being evicted.
            for (var i = previous.size(); i > 0; i--) {
                var candidate = previous[i - 1];
                if (candidate instanceof String && !(candidate as String).equals(key) &&
                    keys.size() < 1) {
                    keys.add(candidate);
                }
            }
            Storage.setValue(storageKey, {
                "at" => Time.now().value(), "g" => tile["g"], "tile" => tile
            } as PropertyValueType);
            keys.add(key);
            try {
                Storage.setValue(indexKey, keys as PropertyValueType);
            } catch (e) {
                Storage.deleteValue(storageKey);
                return;
            }
            for (var i = 0; i < previous.size(); i++) {
                if (previous[i] instanceof String && !(previous[i] as String).equals(key) &&
                    !(previous[i] as String).equals(keys[0])) {
                    Storage.deleteValue("nearby:" + previous[i]);
                }
            }
        } catch (e) {
            // Device store may be full. The fetched response is still usable.
        }
    }
}
