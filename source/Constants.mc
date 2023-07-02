import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

(:glance)
class Constants {
    static const REFRESH_DELAY_S = 10;

    (:roundScreen)
    static const LINES_TO_SHOW = 5;
    (:semioctagonalScreen)
    static const LINES_TO_SHOW = 4;

    static const VERTICAL_SPACE as Number = 2;

    (:roundScreen)
    static const HORIZONTAL_SPACE as Number = 1;
    (:semioctagonalScreen)
    static const HORIZONTAL_SPACE as Number = 1;

    (:roundScreen)
    static const HORIZONTAL_SPACE_SYMBOLS as Number = 2;
    (:semioctagonalScreen)
    static const HORIZONTAL_SPACE_SYMBOLS as Number = 4;

    static const LINE_WIDTH as Number = 3;

    (:semioctagonalScreen)
    static const SEMIOCTAGONAL_CORNER_HEIGHT = 33;

    (:semioctagonalScreen)
    static const SUB_WINDOW_X = 113;

    (:semioctagonalScreen)
    static const SUB_WINDOW_Y = 1;

    (:semioctagonalScreen)
    static const SUB_WINDOW_SIZE = 62;

    static const COLOUR_BACKGROUND as Number = Graphics.COLOR_BLACK;
    static const COLOUR_FOREGROUND as Number = Graphics.COLOR_WHITE;

    static const NO_STOPS_STRING as String = WatchUi.loadResource(Rez.Strings.NoStops) as String;
    static const NO_BUSES_STRING as String = WatchUi.loadResource(Rez.Strings.NoBuses) as String;
}
