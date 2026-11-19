import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// A single outstanding tile per reader. The callback receives (result, context,
// stale); context borrows the tile's rows and optional validated service data.
(:nearby)
class ChristchurchBusTileReader {
    static const READY = 0;
    static const NO_STOPS = 1;
    static const OFFLINE = 2;
    static const UNAVAILABLE = 3;
    static const DEFAULT_URL = "https://mikeller.github.io/garmin-christchurch-bus-widget";
    static const TTL_SECONDS = 259200; // three days
    static const MAX_STOPS = 292;
    static const MAX_BYTES = 4096;
    private static const INDEX_KEY = "nearby:tiles";

    private var pendingKey as String?;
    private var pendingCallback as Method?;
    private var indexKey as String = INDEX_KEY;
    private var failureCode as Number = 0;
    // Only the last validated tile is held in memory. Its Storage record may
    // be evicted, so invalidate this memo on every write or deletion path.
    private var memoKey as String?;
    private var memoTile as Dictionary?;
    private var memoAt as Number = 0;

    function getFailureCode() as Number {
        return failureCode;
    }

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
        NearbyWorkCount.validate();
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
        for (var i = 0; i < date.length(); i++) { NearbyWorkCount.iteration();
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
        if (list.size() > MAX_STOPS) {
            return false;
        }
        var previousCode = 0;
        for (var i = 0; i < list.size(); i++) { NearbyWorkCount.iteration();
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
            if ((row[0] as Number) <= previousCode) {
                return false;
            }
            previousCode = row[0] as Number;
        }
        // Reject a core that cannot possibly fit the producer's 4096-byte
        // payload cap. Unknown root keys are tolerated for forward compatibility.
        var minimum = 20;
        for (var j = 0; j < list.size(); j++) { NearbyWorkCount.iteration();
            var row = list[j] as Array;
            minimum += (row[0] as Number).toString().length() +
                (row[1] as Number).toString().length() +
                (row[2] as Number).toString().length() +
                (row[3] as String).length() + 8;
            if (minimum > MAX_BYTES) {
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
            callback.invoke(READY, cached, false);
            return true;
        }
        if (!System.getDeviceSettings().connectionAvailable) {
            failureCode = -104;
            deliverOffline(key, callback);
            return true;
        }
        // An expired but validated tile can still populate the page list
        // immediately while a replacement tile is requested.
        var stale = readCache(key, true);
        if (stale != null) {
            callback.invoke(READY, stale, true);
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
            failureCode = -1;
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
        failureCode = responseCode;
        var result = resultFor(responseCode, body);
        if (result == READY) {
            var tile = body as Dictionary;
            var context = tile;
            writeCache(key as String, tile);
            callback.invoke(READY, context, false);
        } else if (result == OFFLINE) {
            deliverOffline(key as String, callback as Method);
        } else {
            callback.invoke(result, null, false);
        }
    }

    private function deliverOffline(key as String, callback as Method) as Void {
        var stale = readCache(key, true);
        if (stale != null) {
            callback.invoke(READY, stale, true);
        } else {
            callback.invoke(OFFLINE, null, false);
        }
    }

    function readCache(key as String, allowExpired as Boolean) as Dictionary? {
        try {
            var now = Time.now().value();
            if (INDEX_KEY.equals(indexKey) && memoKey != null && (memoKey as String).equals(key) &&
                memoTile != null && now >= memoAt &&
                (allowExpired || now - memoAt < TTL_SECONDS)) {
                return memoTile;
            }
            NearbyWorkCount.read();
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
                if (memoKey != null && (memoKey as String).equals(key)) {
                    memoKey = null;
                    memoTile = null;
                }
                return null;
            }
            if (!allowExpired && (Time.now().value() - (fetched as Number) >= TTL_SECONDS ||
                                   Time.now().value() < (fetched as Number))) {
                return null;
            }
            memoKey = key;
            memoTile = tile as Dictionary;
            memoAt = fetched as Number;
            return tile as Dictionary;
        } catch (e) {
            return null;
        }
    }

    // Only inspect validated, unexpired tiles already in Storage. A title
    // lookup must never start another network request or Position acquisition.
    function cachedRowsFor(stopId as Number) as Array? {
        NearbyWorkCount.title();
        try {
            if (INDEX_KEY.equals(indexKey) && memoTile != null && Time.now().value() >= memoAt &&
                Time.now().value() - memoAt < TTL_SECONDS) {
                var memoRows = (memoTile as Dictionary)["s"] as Array;
                for (var m = 0; m < memoRows.size(); m++) {
                    NearbyWorkCount.iteration();
                    if ((memoRows[m] as Array)[0] == stopId) {
                        return memoRows;
                    }
                }
            }
            NearbyWorkCount.read();
            var stored = Storage.getValue(indexKey);
            if (!(stored instanceof Array)) {
                return null;
            }
            var keys = stored as Array;
            for (var i = keys.size(); i > 0; i--) {
                NearbyWorkCount.iteration();
                var key = keys[i - 1];
                if (!(key instanceof String)) {
                    continue;
                }
                var tile = readCache(key as String, false);
                if (tile == null) {
                    continue;
                }
                var rows = (tile as Dictionary)["s"] as Array;
                for (var j = 0; j < rows.size(); j++) {
                    NearbyWorkCount.iteration();
                    var row = rows[j] as Array;
                    if ((row[0] as Number) == stopId) {
                        return rows;
                    }
                }
            }
        } catch (e) {
            // A malformed or obsolete cache must not prevent favourite pages.
        }
        return null;
    }

    function writeCache(key as String, tile as Dictionary) as Void {
        memoKey = null;
        memoTile = null;
        // The documented per-value cap is 32 KB; actual object-store capacity
        // varies by device. A tile is <= 4096 UTF-8 bytes on the wire, but
        // parsed objects have overhead. A failed write must not lose the tile
        // just fetched or affect live departures.
        var storageKey = "nearby:" + key;
        try {
            NearbyWorkCount.read();
            var old = Storage.getValue(indexKey);
            var previous = old instanceof Array ? old as Array : [] as Array;
            var keys = [] as Array;
            // Index order is oldest to newest. Retain the most recently used
            // previous tile, not the oldest one being evicted.
            for (var i = previous.size(); i > 0; i--) { NearbyWorkCount.iteration();
                var candidate = previous[i - 1];
                if (candidate instanceof String && !(candidate as String).equals(key) &&
                    keys.size() < 1) {
                    keys.add(candidate);
                }
            }
            storeCacheValue(storageKey, {
                "at" => Time.now().value(), "g" => tile["g"], "tile" => tile
            } as PropertyValueType);
            keys.add(key);
            try {
                storeCacheValue(indexKey, keys as PropertyValueType);
            } catch (e) {
                Storage.deleteValue(storageKey);
                return;
            }
            for (var i = 0; i < previous.size(); i++) { NearbyWorkCount.iteration();
                if (previous[i] instanceof String && !(previous[i] as String).equals(key) &&
                    !(previous[i] as String).equals(keys[0])) {
                    Storage.deleteValue("nearby:" + previous[i]);
                }
            }
        } catch (e) {
            // Device store may be full. The fetched response is still usable.
        }
    }

    // Separated so a pure test reader can exercise the write-exception path.
    function storeCacheValue(key as String, value as PropertyValueType) as Void {
        Storage.setValue(key, value);
    }

}
