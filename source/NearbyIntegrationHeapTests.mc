import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;
import Toybox.Time;

// Simulator-only observations. The SDK has parsed network JSON before the
// reader runs; these constructed objects do not measure the JSON parser.
(:debug, :nearby)
class NearbyIntegrationHeapFixture {
    static function sample(start as Number, count as Number, name as String) as Dictionary {
        var rows = [] as Array;
        var keys = [] as Array;
        for (var i = 0; i < count; i++) {
            rows.add([start + i, 100 + i, 200 + i, name]);
            keys.add(i == count - 1 ? "01" : "00");
        }
        return {"v" => 1, "g" => "2026-11-18", "s" => rows,
            "m" => 2, "sh" => NearbyServiceTestData.DIGEST,
            "K" => 1296, "i" => keys, "p" => []} as Dictionary;
    }

    static function snapshot(label as String, started as Number) as Void {
        var stats = System.getSystemStats();
        System.println("HEAP " + label + " free=" + stats.freeMemory +
            " used=" + stats.usedMemory + " total=" + stats.totalMemory +
            " elapsedMs=" + (System.getTimer() - started));
    }

    static function repeat(value as String, count as Number) as String {
        var result = "";
        for (var i = 0; i < count; i++) {
            result += value;
        }
        return result;
    }
}

(:test, :nearby)
function testNearbyIntegratedHeap(logger as Logger) as Boolean {
    var reader = new ChristchurchBusTileReader();
    reader.useTestIndex();
    Storage.deleteValue("nearby:heap-a");
    Storage.deleteValue("nearby:heap-b");
    Storage.deleteValue("nearby:heap-c");
    Storage.deleteValue("nearby:test-index");
    var tick = System.getTimer();
    NearbyIntegrationHeapFixture.snapshot("baseline", tick);
    try {
        // Compact JSON of this shape is 3826 bytes (56 stops, 43-byte
        // ASCII name); the test constructs the already-parsed equivalent.
        var tile = NearbyIntegrationHeapFixture.sample(1001, 56,
            NearbyIntegrationHeapFixture.repeat("S", 43));
        NearbyIntegrationHeapFixture.snapshot("constructed-56", tick);
        Test.assertMessage(ChristchurchBusTileReader.validTile(tile), "56 core");
        Test.assertMessage(NearbyServiceContext.usable(tile), "56 metadata");
        var context = NearbyServiceContext.context(tile, true);
        NearbyIntegrationHeapFixture.snapshot("validated-56", tick);
        var favourites = [] as Array<Number>;
        for (var i = 0; i < 16; i++) {
            favourites.add(1001 + i);
        }
        var selected = NearbyCoverageSelection.select([context], 100, 200, favourites, 5);
        Test.assertMessage((selected[0] as Array).size() <= 5, "nearby target");
        NearbyIntegrationHeapFixture.snapshot("selected-16-favourites", tick);
        reader.writeCache("heap-a", tile);
        Test.assertMessage(Storage.getValue("nearby:heap-a") != null, "first stored");
        NearbyIntegrationHeapFixture.snapshot("first-write", tick);
        var second = NearbyIntegrationHeapFixture.sample(2001, 56, "Second synthetic corridor stop");
        reader.writeCache("heap-b", second);
        Test.assertMessage(Storage.getValue("nearby:heap-b") != null, "second stored");
        NearbyIntegrationHeapFixture.snapshot("two-cached", tick);
        var reloaded = reader.readCache("heap-a", false);
        Test.assertMessage(reloaded != null, "first reload");
        NearbyIntegrationHeapFixture.snapshot("reloaded", tick);
        var third = NearbyIntegrationHeapFixture.sample(3001, 56, "Fresh synthetic corridor stop");
        Test.assertMessage(NearbyServiceContext.usable(third), "third valid");
        reader.writeCache("heap-c", third);
        Test.assertMessage(Storage.getValue("nearby:heap-c") != null, "third stored");
        Test.assertMessage(Storage.getValue("nearby:heap-a") == null, "oldest evicted");
        Test.assertMessage(reader.readCache("heap-b", false) != null, "second retained");
        NearbyIntegrationHeapFixture.snapshot("evicted-reloaded", tick);
        // Compact JSON of this synthetic shape is exactly 4096 bytes:
        // 56 x 47-byte names plus 46 extra ASCII bytes in the first name.
        var boundary = NearbyIntegrationHeapFixture.sample(4001, 56,
            NearbyIntegrationHeapFixture.repeat("S", 47));
        var boundaryRows = boundary["s"] as Array;
        var firstRow = boundaryRows[0] as Array;
        firstRow[3] = NearbyIntegrationHeapFixture.repeat("S", 93);
        Test.assertMessage(ChristchurchBusTileReader.validTile(boundary), "4096 core");
        Test.assertMessage(NearbyServiceContext.usable(boundary), "4096 metadata");
        NearbyIntegrationHeapFixture.snapshot("boundary-4096", tick);
        // 56 x 100-byte names exceed even the conservative core lower
        // bound; a rejected response must never enter the receive/write path.
        var oversized = NearbyIntegrationHeapFixture.sample(4001, 56,
            NearbyIntegrationHeapFixture.repeat("S", 100));
        Test.assertMessage(!ChristchurchBusTileReader.validTile(oversized),
            "oversized core rejected");
        Test.assertEqualMessage(ChristchurchBusTileReader.UNAVAILABLE,
            ChristchurchBusTileReader.resultFor(200, oversized), "no cacheable response");
        var largeKey = NearbyIntegrationHeapFixture.sample(5001, 1, "Bounded keys");
        var encoded = "";
        for (var i = 0; i < 1296; i++) {
            var digits = "0123456789abcdefghijklmnopqrstuvwxyz";
            encoded += digits.substring(i / 36, i / 36 + 1) +
                digits.substring(i % 36, i % 36 + 1);
        }
        var keyArray = largeKey["i"] as Array;
        keyArray[0] = encoded;
        Test.assertMessage(NearbyServiceContext.usable(largeKey), "1296 distinct keys");
        NearbyIntegrationHeapFixture.snapshot("bounded-1296-keys", tick);
    } finally {
        Storage.deleteValue("nearby:heap-a");
        Storage.deleteValue("nearby:heap-b");
        Storage.deleteValue("nearby:heap-c");
        Storage.deleteValue("nearby:test-index");
    }
    return true;
}
