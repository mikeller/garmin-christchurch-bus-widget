import Toybox.WatchUi;
import Toybox.Lang;

class ChristchurchBusBehaviorDelegate extends WatchUi.BehaviorDelegate {
    protected var displayBusesForCurrentStop as Method() as Void or Null;
    protected var nextStop as Method() as Void;

    function initialize(displayBusesForCurrentStop as Method() as Void or Null, nextStop as Method() as Void) {
        BehaviorDelegate.initialize();

        self.displayBusesForCurrentStop = displayBusesForCurrentStop;
        self.nextStop = nextStop;
    }

    function onSelect() {
        nextStop.invoke();
        if (displayBusesForCurrentStop != null) {
            (displayBusesForCurrentStop as Method() as Void).invoke();
        }
        // Select is handled here; do not pass it back to the widget stack.
        return true;
    }

    function onBack() as Boolean {
        // Let the platform dismiss the base widget view. popView() is not
        // permitted there, and consuming Back would strand the widget.
        return false;
    }

    function onNextPage() as Boolean {
        // Down belongs to the widget carousel on non-glance devices.
        return false;
    }
}
