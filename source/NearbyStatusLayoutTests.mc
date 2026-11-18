import Toybox.Lang;
import Toybox.Test;

(:debug, :nearby)
class NearbyStatusTestMeasure {
    function width(text as String) as Number {
        return text.length() * 10;
    }
}

(:test, :nearby)
function testNearbyStatusWrapping(logger as Logger) as Boolean {
    var measure = new NearbyStatusTestMeasure();
    var width = measure.method(:width);
    var title = NearbyStatusLayout.wrap("Nearby unavailable", 180, width, 2);
    Test.assertEqualMessage(1, (title as Array).size(), "title line count");
    Test.assertEqualMessage("Nearby unavailable", (title as Array)[0], "title fits");
    var hint = NearbyStatusLayout.wrap("Check location; reopen outdoors", 180, width, 2);
    Test.assertEqualMessage(2, (hint as Array).size(), "hint line count");
    Test.assertEqualMessage("Check location;", (hint as Array)[0], "first hint line");
    Test.assertEqualMessage("reopen outdoors", (hint as Array)[1], "second hint line");
    Test.assertEqualMessage(3, (title as Array).size() + (hint as Array).size(), "three-line state");
    Test.assertEqualMessage("Locating...", (NearbyStatusLayout.wrap("Locating...", 180, width, 2) as Array)[0],
        "loading fits");
    Test.assertEqualMessage("No stops nearby", (NearbyStatusLayout.wrap("No stops nearby", 180, width, 2) as Array)[0],
        "empty tile fits");
    var settings = NearbyStatusLayout.wrap("Configure stops in settings", 180, width, 2);
    Test.assertEqualMessage("Configure stops in", (settings as Array)[0], "settings hint wraps");
    Test.assertEqualMessage("settings", (settings as Array)[1], "second settings line");
    var longWord = NearbyStatusLayout.wrap("abcdefghijklmnopqr", 100, width, 2);
    Test.assertEqualMessage("abcdefghij", (longWord as Array)[0], "long word first line");
    Test.assertEqualMessage("klmnopqr", (longWord as Array)[1], "long word second line");
    Test.assertMessage(NearbyStatusLayout.wrap("one two three four", 50, width, 2) == null,
        "more than two lines is rejected for a larger font");
    return true;
}
