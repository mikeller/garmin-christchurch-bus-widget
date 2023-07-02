import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:glance)
class ChristchurchBusGlanceView extends WatchUi.GlanceView {
    private var stop as Dictionary<String, Number or String>?;
    private var glanceTitle as String = WatchUi.loadResource(Rez.Strings.AppName) as String;

    function initialize(stop as Dictionary?) {
        GlanceView.initialize();

        self.stop = stop as Dictionary<String, Number or String>?;
    }

    function onLayout(dc as Dc) as Void {
        try {
            if (stop != null) {
                var stopId = stop["stopId"] as Number;

                var displayName = stop["displayName"] as String;
                if ("".equals(displayName)) {
                    glanceTitle = "" + stopId;
                } else {
                    glanceTitle = displayName;
                }

                var cache = null;
                try {
                     cache = ChristchurchBusDataCache.tryGetCachedData(stopId, true);
                } catch (exception instanceof Exception) {
                    Utils.log("Problem loading cache: " + exception.getErrorMessage());
                    exception.printStackTrace();
                }

                if (cache != null) {
                    //TODO: load glance content
                }
            }
        } catch (exception instanceof UnexpectedTypeException) {
            Utils.log("Data format problem: " + exception.getErrorMessage());
            exception.printStackTrace();
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(0, 0, Graphics.FONT_SYSTEM_TINY, glanceTitle, Graphics.TEXT_JUSTIFY_LEFT);

        var lineHeight = dc.getFontHeight(Graphics.FONT_SYSTEM_TINY);
        var secondLineY = lineHeight + Constants.VERTICAL_SPACE;

        //TODO: draw glance content
    }
}
