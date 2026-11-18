import Toybox.Lang;
import Toybox.Test;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Time;

// Mirrors tools/stoptiles/service_key_vectors.json at ded50bbec0f0f5e5,
// global_cases exactly; historical cases are unsupported m=1 fallback.
(:debug, :nearby)
class NearbyServiceTestData {
    static const DIGEST = "0000000000000000000000000000000000000000000000000000000000000000";
    static function tile() as Dictionary {
        return {"v" => 1, "g" => "2026-11-18",
                "s" => [[1001, 0, 0, "A"], [1002, 0, 1, "B"], [1003, 0, 2, "C"]],
                "m" => 2, "sh" => DIGEST, "K" => 60,
                "i" => ["000z", "0z", null], "p" => [1002]} as Dictionary;
    }
    static function one() as Dictionary {
        return {"v" => 1, "g" => "2026-11-18",
                "s" => [[1001, 0, 0, "A"]],
                "m" => 2, "sh" => DIGEST, "K" => 60,
                "i" => ["00"], "p" => []} as Dictionary;
    }
}

(:debug, :nearby)
class FailingServiceCacheReader extends ChristchurchBusTileReader {
    function storeCacheValue(key as String, value as PropertyValueType) as Void {
        throw new Lang.Exception();
    }
}

(:test, :nearby)
function testGlobalServiceVectors(logger as Logger) as Boolean {
    var tile = NearbyServiceTestData.tile();
    Test.assertMessage(NearbyServiceContext.usable(tile), "known_partial_unknown");
    var context = NearbyServiceContext.context(tile, true);
    Test.assertEqualMessage("000z", (context["i"] as Array)[0], "complete {0,35}");
    Test.assertEqualMessage("0z", (context["i"] as Array)[1], "partial {35}");
    Test.assertMessage((context["i"] as Array)[2] == null, "unknown");
    Test.assertEqualMessage(1002, (context["p"] as Array)[0], "partial code");
    tile = NearbyServiceTestData.one();
    tile["s"] = [[1004, 0, 0, "D"]];
    tile["i"] = ["0z"];
    Test.assertMessage(NearbyServiceContext.usable(tile), "different_tile_same_global_index");
    tile = NearbyServiceTestData.one();
    tile["i"] = ["1o"];
    Test.assertMessage(!NearbyServiceContext.usable(tile), "index_out_of_bounds");
    tile["i"] = ["0000"];
    Test.assertMessage(!NearbyServiceContext.usable(tile), "duplicate_index");
    tile["i"] = [null];
    tile["p"] = [1001];
    Test.assertMessage(!NearbyServiceContext.usable(tile), "partial_unknown");
    tile["p"] = [];
    tile["i"] = ["0"];
    Test.assertMessage(!NearbyServiceContext.usable(tile), "malformed_odd_length");
    return true;
}

(:test, :nearby)
function testServiceInvalidMetadataFallback(logger as Logger) as Boolean {
    var tile = NearbyServiceTestData.one();
    var invalid = ["", "0", "0A", "0é", "0100", "0000", "zz"];
    for (var j = 0; j < invalid.size(); j++) {
        tile["i"] = [invalid[j]];
        Test.assertMessage(ChristchurchBusTileReader.validTile(tile), "valid core " + j);
        Test.assertMessage(NearbyServiceContext.context(tile, true)["i"] == null, "unknown " + j);
    }
    tile = NearbyServiceTestData.one();
    tile["K"] = 1;
    Test.assertMessage(NearbyServiceContext.usable(tile), "K=1");
    tile["K"] = 1296;
    tile["i"] = ["zz"];
    Test.assertMessage(NearbyServiceContext.usable(tile), "K=1296 id=1295");
    tile["K"] = 0;
    Test.assertMessage(!NearbyServiceContext.usable(tile), "K=0");
    tile["K"] = 1297;
    Test.assertMessage(!NearbyServiceContext.usable(tile), "K=1297");
    tile["K"] = true;
    Test.assertMessage(!NearbyServiceContext.usable(tile), "boolean K");
    tile["K"] = "60";
    Test.assertMessage(!NearbyServiceContext.usable(tile), "string K");
    tile["K"] = 60;
    tile["i"] = ["00"];
    tile["m"] = true;
    Test.assertMessage(!NearbyServiceContext.usable(tile), "boolean version");
    tile["m"] = 1;
    Test.assertMessage(!NearbyServiceContext.usable(tile), "historical dictionary m=1");
    tile["m"] = 2;
    tile["i"] = [];
    Test.assertMessage(!NearbyServiceContext.usable(tile), "i/s mismatch");
    tile["i"] = ["00"];
    tile["p"] = [1002];
    Test.assertMessage(!NearbyServiceContext.usable(tile), "p not in tile");
    tile["p"] = [1001, 1001];
    Test.assertMessage(!NearbyServiceContext.usable(tile), "duplicate p");
    tile["p"] = [];
    tile["sh"] = "abc";
    Test.assertMessage(!NearbyServiceContext.usable(tile), "short sh");
    tile["sh"] = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF";
    Test.assertMessage(!NearbyServiceContext.usable(tile), "uppercase sh");
    tile["sh"] = NearbyServiceTestData.DIGEST;
    tile["i"] = [null];
    Test.assertMessage(NearbyServiceContext.usable(tile), "all unknown is valid");
    tile["i"] = ["00"];
    tile["p"] = "wrong type";
    Test.assertMessage(!NearbyServiceContext.usable(tile), "p wrong type");
    tile["p"] = [];
    tile["i"] = ["00"];
    tile["K"] = 1296;
    var tooMany = "";
    for (var j = 0; j < 2049; j++) {
        tooMany += "00";
    }
    tile["i"] = [tooMany];
    Test.assertMessage(!NearbyServiceContext.usable(tile), "oversized parsed metadata");
    tile["s"] = [[1001, 0, 0, "A"], [1001, 0, 1, "B"]];
    Test.assertMessage(!ChristchurchBusTileReader.validTile(tile), "duplicate s");
    return true;
}

(:test, :nearby)
function testServiceCandidateConsistency(logger as Logger) as Boolean {
    var one = NearbyServiceContext.context(NearbyServiceTestData.one(), true);
    var two = NearbyServiceContext.context(NearbyServiceTestData.one(), true);
    Test.assertMessage(NearbyServiceContext.consistent([one]), "one tile");
    Test.assertMessage(NearbyServiceContext.consistent([one, two]), "same generation");
    two["sh"] = "1111111111111111111111111111111111111111111111111111111111111111";
    Test.assertMessage(!NearbyServiceContext.consistent([one, two]), "different digest");
    two["sh"] = one["sh"];
    two["K"] = 61;
    Test.assertMessage(!NearbyServiceContext.consistent([one, two]), "different K");
    two["K"] = 60;
    two["g"] = "2026-11-19";
    Test.assertMessage(!NearbyServiceContext.consistent([one, two]), "same digest different g");
    two["g"] = one["g"];
    two["sh"] = null;
    Test.assertMessage(!NearbyServiceContext.consistent([one, two]), "legacy beside fresh");
    Test.assertMessage(!NearbyServiceContext.consistent([]), "no candidates");
    Test.assertMessage(NearbyServiceContext.context(NearbyServiceTestData.one(), false)["i"] == null,
        "stale is unknown");
    return true;
}

(:test, :nearby)
function testServiceCacheFallback(logger as Logger) as Boolean {
    var reader = new ChristchurchBusTileReader();
    reader.useTestIndex();
    var key = "test-service";
    Storage.deleteValue("nearby:" + key);
    Storage.deleteValue("nearby:test-index");
    try {
        var tile = NearbyServiceTestData.one();
        reader.writeCache(key, tile);
        var cached = reader.readCache(key, false);
        Test.assertMessage(cached != null && NearbyServiceContext.usable(cached as Dictionary),
            "fresh metadata");
        var stored = Storage.getValue("nearby:" + key) as Dictionary;
        stored["g"] = "2026-11-17";
        Storage.setValue("nearby:" + key, stored as PropertyValueType);
        Test.assertMessage(reader.readCache(key, true) == null, "wrapper g mismatch");
        tile = NearbyServiceTestData.one();
        reader.writeCache(key, tile);
        stored = Storage.getValue("nearby:" + key) as Dictionary;
        stored["at"] = 0;
        Storage.setValue("nearby:" + key, stored as PropertyValueType);
        cached = reader.readCache(key, true);
        Test.assertMessage(cached != null && NearbyServiceContext.context(cached as Dictionary, true)["i"] == null,
            "expired metadata stripped");
        tile = NearbyServiceTestData.one();
        tile.remove("m");
        tile.remove("sh");
        tile.remove("K");
        tile.remove("i");
        tile.remove("p");
        reader.writeCache(key, tile);
        cached = reader.readCache(key, false);
        Test.assertMessage(cached != null && NearbyServiceContext.context(cached as Dictionary, true)["i"] == null,
            "legacy cache all unknown");
        stored = Storage.getValue("nearby:" + key) as Dictionary;
        stored["at"] = 0;
        Storage.setValue("nearby:" + key, stored as PropertyValueType);
        Test.assertMessage(reader.readCache(key, false) == null, "expired");
        Test.assertMessage(reader.readCache(key, true) != null, "expired legacy rows");
        stored["at"] = Time.now().value() + 600;
        Storage.setValue("nearby:" + key, stored as PropertyValueType);
        Test.assertMessage(reader.readCache(key, false) == null, "backward clock");
        Test.assertMessage(reader.readCache(key, true) != null, "future legacy rows");
        // The real write path catches object-store exceptions, including on
        // small-memory devices. A failed write cannot invalidate live data.
        var live = NearbyServiceContext.context(NearbyServiceTestData.one(), true);
        Storage.deleteValue("nearby:" + key);
        var failing = new FailingServiceCacheReader();
        failing.useTestIndex();
        failing.writeCache(key, NearbyServiceTestData.one());
        Test.assertMessage(Storage.getValue("nearby:" + key) == null, "failed write not retained");
        Test.assertMessage(NearbyServiceContext.consistent([live]), "cache write independent");
    } finally {
        Storage.deleteValue("nearby:" + key);
        Storage.deleteValue("nearby:test-index");
    }
    return true;
}
