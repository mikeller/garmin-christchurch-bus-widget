import Toybox.Lang;
import Toybox.System;

// Host diagnostic only. The release implementation has no counters.
(:debug, :nearby)
class NearbyWorkBudget {
    static var reads as Number = 0;
    static var validates as Number = 0;
    static var titles as Number = 0;
    static var distances as Number = 0;
    static var iterations as Number = 0;
    static var visits as Number = 0;
    static var tileCallbacks as Number = 0;
    static var pageRebuilds as Number = 0;
    static var displayBuilds as Number = 0;
    static var displayDistances as Number = 0;
    static var start as Number = 0;
    static var active as Boolean = false;

    static function begin() as Void {
        reads = 0;
        validates = 0;
        titles = 0;
        distances = 0;
        iterations = 0;
        visits = 0;
        tileCallbacks = 0;
        pageRebuilds = 0;
        displayBuilds = 0;
        displayDistances = 0;
        start = System.getTimer();
        active = true;
    }

    static function beginIfIdle() as Void {
        if (!active) {
            begin();
        }
    }

    static function report() as Void {
        System.println("Nearby work budget: ms=" + (System.getTimer() - start) +
            " storage=" + reads + " validates=" + validates +
            " titles=" + titles + " distance=" + distances +
            " iterations=" + iterations + " visits=" + visits);
        active = false;
    }
}

(:release, :nearby)
class NearbyWorkBudget {
    static function begin() as Void {}
    static function beginIfIdle() as Void {}
    static function report() as Void {}
    static function read() as Void {}
    static function validate() as Void {}
    static function title() as Void {}
    static function distance() as Void {}
    static function iteration() as Void {}
    static function visit() as Void {}
    static function tile() as Void {}
    static function rebuild() as Void {}
    static function display() as Void {}
    static function displayDistance() as Void {}
}

(:debug, :nearby)
class NearbyWorkCount {
    static function read() as Void { NearbyWorkBudget.reads++; }
    static function validate() as Void { NearbyWorkBudget.validates++; }
    static function title() as Void { NearbyWorkBudget.titles++; }
    static function distance() as Void { NearbyWorkBudget.distances++; }
    static function iteration() as Void { NearbyWorkBudget.iterations++; }
    static function visit() as Void { NearbyWorkBudget.visits++; }
    static function tile() as Void { NearbyWorkBudget.tileCallbacks++; }
    static function rebuild() as Void { NearbyWorkBudget.pageRebuilds++; }
    static function display() as Void { NearbyWorkBudget.displayBuilds++; }
    static function displayDistance() as Void { NearbyWorkBudget.displayDistances++; }
}

(:release, :nearby)
class NearbyWorkCount {
    static function read() as Void {}
    static function validate() as Void {}
    static function title() as Void {}
    static function distance() as Void {}
    static function iteration() as Void {}
    static function visit() as Void {}
    static function tile() as Void {}
    static function rebuild() as Void {}
    static function display() as Void {}
    static function displayDistance() as Void {}
}
