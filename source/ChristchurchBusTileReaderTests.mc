import Toybox.Lang;
import Toybox.Test;
import Toybox.Application;
import Toybox.Application.Storage;

(:debug, :nearby)
class ChristchurchBusTileTestData {
    static function tile() as Dictionary {
        return {"v" => 1, "g" => "2026-11-13",
                "s" => [[53090, -4353100, 17263700, "Rāpaki Rd near Main Rd"]]} as Dictionary;
    }
}

(:test, :nearby)
function testTileValidation(logger as Logger) as Boolean {
    var tile = ChristchurchBusTileTestData.tile();
    Test.assertMessage(ChristchurchBusTileReader.validTile(tile), "valid raw name");
    tile["s"] = [] as Array;
    Test.assertMessage(ChristchurchBusTileReader.validTile(tile), "empty tile");
    tile["v"] = 2;
    Test.assertMessage(!ChristchurchBusTileReader.validTile(tile), "version");
    tile["v"] = 1;
    tile["g"] = "2026-13-40";
    Test.assertMessage(!ChristchurchBusTileReader.validTile(tile), "invalid date");
    tile["g"] = "2026-11-13";
    tile["s"] = "not an array";
    Test.assertMessage(!ChristchurchBusTileReader.validTile(tile), "s type");
    tile["s"] = [[53090, -4353100, 17263700]] as Array;
    Test.assertMessage(!ChristchurchBusTileReader.validTile(tile), "row length");
    tile["s"] = [[999, -4353100, 17263700, "Name"]] as Array;
    Test.assertMessage(!ChristchurchBusTileReader.validTile(tile), "code lower bound");
    tile["s"] = [[100000, -4353100, 17263700, "Name"]] as Array;
    Test.assertMessage(!ChristchurchBusTileReader.validTile(tile), "code upper bound");
    tile["s"] = [[53090, "-4353100", 17263700, "Name"]] as Array;
    Test.assertMessage(!ChristchurchBusTileReader.validTile(tile), "coordinate type");
    tile["s"] = [[53090, -4353100, 17263700, 12]] as Array;
    Test.assertMessage(!ChristchurchBusTileReader.validTile(tile), "name type");
    Test.assertMessage(!ChristchurchBusTileReader.validTile(null), "null");
    Test.assertMessage(!ChristchurchBusTileReader.validTile([] as Array), "root type");
    return true;
}

(:test, :nearby)
function testTileResponses(logger as Logger) as Boolean {
    var valid = ChristchurchBusTileTestData.tile();
    Test.assertEqualMessage(ChristchurchBusTileReader.READY, ChristchurchBusTileReader.resultFor(200, valid), "200 JSON");
    Test.assertEqualMessage(ChristchurchBusTileReader.NO_STOPS, ChristchurchBusTileReader.resultFor(-400, null), "404 HTML");
    Test.assertEqualMessage(ChristchurchBusTileReader.OFFLINE, ChristchurchBusTileReader.resultFor(-104, null), "BLE");
    Test.assertEqualMessage(ChristchurchBusTileReader.UNAVAILABLE, ChristchurchBusTileReader.resultFor(-403, null), "out of memory");
    Test.assertEqualMessage(ChristchurchBusTileReader.UNAVAILABLE, ChristchurchBusTileReader.resultFor(200, null), "empty body");
    Test.assertEqualMessage(ChristchurchBusTileReader.UNAVAILABLE, ChristchurchBusTileReader.resultFor(500, valid), "server error");
    valid["v"] = 0;
    Test.assertEqualMessage(ChristchurchBusTileReader.UNAVAILABLE, ChristchurchBusTileReader.resultFor(200, valid), "wrong version");
    return true;
}

(:test, :nearby)
function testTileCacheBoundAndExpiry(logger as Logger) as Boolean {
    var reader = new ChristchurchBusTileReader();
    reader.useTestIndex();
    var tile = ChristchurchBusTileTestData.tile();
    var keys = ["test-a", "test-b", "test-c"];
    // Storage persists between simulator tests and test runs.
    Storage.deleteValue("nearby:test-index");
    for (var i = 0; i < keys.size(); i++) {
        Storage.deleteValue("nearby:" + keys[i]);
    }
    for (var i = 0; i < keys.size(); i++) {
        reader.writeCache(keys[i], tile);
        Test.assertMessage(reader.readCache(keys[i], false) != null, "fresh cache " + i);
    }
    Test.assertMessage(reader.readCache(keys[0], true) == null, "evicted oldest");
    Test.assertMessage(reader.readCache(keys[1], true) != null, "second remains");
    Test.assertMessage(reader.readCache(keys[2], true) != null, "third remains");
    var stored = Storage.getValue("nearby:test-b") as Dictionary;
    stored["at"] = 0;
    Storage.setValue("nearby:test-b", stored as PropertyValueType);
    Test.assertMessage(reader.readCache(keys[1], false) == null, "expired");
    Test.assertMessage(reader.readCache(keys[1], true) != null, "offline stale");
    for (var i = 0; i < keys.size(); i++) {
        Storage.deleteValue("nearby:" + keys[i]);
    }
    Storage.deleteValue("nearby:test-index");
    return true;
}

(:test, :nearby)
function testTileCacheLarge(logger as Logger) as Boolean {
    var reader = new ChristchurchBusTileReader();
    reader.useTestIndex();
    Storage.deleteValue("nearby:test-index");
    Storage.deleteValue("nearby:test-large");
    var tile = ChristchurchBusTileTestData.tile();
    var stops = [] as Array;
    for (var i = 0; i < 56; i++) {
        stops.add([1000 + i, -4353100 + i, 17263700 + i,
                   "Rāpaki Rd near Main Rd (Platform " + i + ")"]);
    }
    tile["s"] = stops;
    Test.assertMessage(ChristchurchBusTileReader.validTile(tile), "56 raw names");
    reader.writeCache("test-large", tile);
    var stored = reader.readCache("test-large", false);
    Test.assertMessage(stored != null, "56-stop tile fits storage");
    if (stored != null) {
        Test.assertEqualMessage(56, (stored["s"] as Array).size(), "all stops retained");
    }
    Storage.deleteValue("nearby:test-large");
    Storage.deleteValue("nearby:test-index");
    return true;
}
