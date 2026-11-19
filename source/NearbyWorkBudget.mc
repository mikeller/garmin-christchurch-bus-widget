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
    static var start as Number = 0;

    static function begin() as Void {
        reads = 0;
        validates = 0;
        titles = 0;
        distances = 0;
        iterations = 0;
        visits = 0;
        start = System.getTimer();
    }

    static function report() as Void {
        System.println("Nearby work budget: ms=" + (System.getTimer() - start) +
            " storage=" + reads + " validates=" + validates +
            " titles=" + titles + " distance=" + distances +
            " iterations=" + iterations + " visits=" + visits);
    }
}

(:release, :nearby)
class NearbyWorkBudget {
    static function begin() as Void {}
    static function report() as Void {}
    static function read() as Void {}
    static function validate() as Void {}
    static function title() as Void {}
    static function distance() as Void {}
    static function iteration() as Void {}
    static function visit() as Void {}
}

(:debug, :nearby)
class NearbyWorkCount {
    static function read() as Void { NearbyWorkBudget.reads++; }
    static function validate() as Void { NearbyWorkBudget.validates++; }
    static function title() as Void { NearbyWorkBudget.titles++; }
    static function distance() as Void { NearbyWorkBudget.distances++; }
    static function iteration() as Void { NearbyWorkBudget.iterations++; }
    static function visit() as Void { NearbyWorkBudget.visits++; }
}

(:release, :nearby)
class NearbyWorkCount {
    static function read() as Void {}
    static function validate() as Void {}
    static function title() as Void {}
    static function distance() as Void {}
    static function iteration() as Void {}
    static function visit() as Void {}
}
