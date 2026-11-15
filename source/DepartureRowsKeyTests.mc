import Toybox.Lang;
import Toybox.Test;
import Toybox.Graphics;

(:test)
function testDepartureRowsKeySameContent(logger as Logger) as Boolean {
    var a = [{"ExpectedDepartureTime" => "2026-11-15T18:32:00+13:00",
              "PublishedLineName" => "8", "DestinationName" => "Lyttelton",
              "VehicleAtStop" => false}];
    var b = [{"ExpectedDepartureTime" => "2026-11-15T18:32:00+13:00",
              "PublishedLineName" => "8", "DestinationName" => "Lyttelton",
              "VehicleAtStop" => false}];
    Test.assertEqualMessage(true, DepartureRowsKey.same(a, b, 194, 194, 240, 240,
        Graphics.FONT_SYSTEM_TINY, Graphics.FONT_SYSTEM_TINY),
                            "independent arrays with the same rows and geometry must match");
    return true;
}

(:test)
function testDepartureRowsKeyChangedContent(logger as Logger) as Boolean {
    var a = [{"ExpectedDepartureTime" => "2026-11-15T18:32:00+13:00",
              "PublishedLineName" => "8", "DestinationName" => "Lyttelton",
              "VehicleAtStop" => false}];
    var b = [{"ExpectedDepartureTime" => "2026-11-15T18:32:00+13:00",
              "PublishedLineName" => "8", "DestinationName" => "Rāpaki",
              "VehicleAtStop" => false}];
    Test.assertEqualMessage(false, DepartureRowsKey.same(a, b, 194, 194, 240, 240,
        Graphics.FONT_SYSTEM_TINY, Graphics.FONT_SYSTEM_TINY),
                            "changed destination must refit");
    b[0]["DestinationName"] = "Lyttelton";
    b[0]["PublishedLineName"] = "29";
    Test.assertEqualMessage(false, DepartureRowsKey.same(a, b, 194, 194, 240, 240,
        Graphics.FONT_SYSTEM_TINY, Graphics.FONT_SYSTEM_TINY),
                            "changed route must refit");
    b[0]["PublishedLineName"] = "8";
    b[0]["ExpectedDepartureTime"] = "2026-11-15T18:33:00+13:00";
    Test.assertEqualMessage(false, DepartureRowsKey.same(a, b, 194, 194, 240, 240,
        Graphics.FONT_SYSTEM_TINY, Graphics.FONT_SYSTEM_TINY),
                            "changed departure must refit");
    b[0]["ExpectedDepartureTime"] = "2026-11-15T18:32:00+13:00";
    b[0]["VehicleAtStop"] = true;
    Test.assertEqualMessage(false, DepartureRowsKey.same(a, b, 194, 194, 240, 240,
        Graphics.FONT_SYSTEM_TINY, Graphics.FONT_SYSTEM_TINY),
                            "changed at-stop state must redraw");
    b[0]["VehicleAtStop"] = false;
    b.add({"ExpectedDepartureTime" => "2026-11-15T18:42:00+13:00",
           "PublishedLineName" => "29", "DestinationName" => "City",
           "VehicleAtStop" => false});
    Test.assertEqualMessage(false, DepartureRowsKey.same(a, b, 194, 194, 240, 240,
        Graphics.FONT_SYSTEM_TINY, Graphics.FONT_SYSTEM_TINY),
                            "changed row count must refit");
    return true;
}

(:test)
function testDepartureRowsKeyChangedGeometry(logger as Logger) as Boolean {
    var rows = [{"ExpectedDepartureTime" => "2026-11-15T18:32:00+13:00",
                 "PublishedLineName" => "8", "DestinationName" => "Lyttelton",
                 "VehicleAtStop" => false}];
    Test.assertEqualMessage(false, DepartureRowsKey.same(rows, rows, 194, 193, 240, 240,
        Graphics.FONT_SYSTEM_TINY, Graphics.FONT_SYSTEM_TINY),
                            "changed width must refit");
    Test.assertEqualMessage(false, DepartureRowsKey.same(rows, rows, 194, 194, 240, 260,
        Graphics.FONT_SYSTEM_TINY, Graphics.FONT_SYSTEM_TINY),
                            "changed height must refit");
    Test.assertEqualMessage(false, DepartureRowsKey.same(rows, rows, 194, 194, 240, 240,
        Graphics.FONT_SYSTEM_SMALL, Graphics.FONT_SYSTEM_TINY),
                            "changed chosen font must refit");
    return true;
}
