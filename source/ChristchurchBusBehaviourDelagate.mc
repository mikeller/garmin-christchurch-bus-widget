import Toybox.WatchUi;

class ChristchurchBusBehaviorDelegate extends WatchUi.BehaviorDelegate {
    protected var displayBusesForCurrentStop as Method() as Void;
    protected var nextStop as Method() as Void;

    function initialize(displayBusesForCurrentStop as Method() as Void, nextStop as Method() as Void) {
        BehaviorDelegate.initialize();

        self.displayBusesForCurrentStop = displayBusesForCurrentStop;
        self.nextStop = nextStop;
    }

    function onSelect() {
        nextStop.invoke();
        displayBusesForCurrentStop.invoke();
        // Select is handled here; do not pass it back to the widget stack.
        return true;
    }
}
