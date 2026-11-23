import Toybox.Lang;

(:nearby)
class NearbyAcquisitionState {
    static const IDLE = 0;
    static const WAITING = 1;
    static const LATE = 2;
    static const FIX = 3;

    static function shown() as Number {
        return WAITING;
    }

    static function timedOut(state as Number) as Number {
        return IDLE;
    }

    static function received(state as Number) as Number {
        return state == WAITING || state == LATE ? FIX : state;
    }

    static function afterHide(state as Number) as Number {
        return IDLE;
    }

    static function registered(state as Number) as Boolean {
        return state == WAITING || state == LATE;
    }
}
