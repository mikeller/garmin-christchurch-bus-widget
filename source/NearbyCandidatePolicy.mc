import Toybox.Lang;

(:nearby)
class NearbyCandidatePolicy {
    // An extra candidate can be fetched once per location session, without
    // taking a ninth request or a second extra in-flight HTTP slot.
    static function shouldRequest(keys as Array?, overflow as Boolean, attempted as Boolean,
                                  onPage as Boolean, running as Boolean,
                                  extraInFlight as Boolean, used as Number) as Boolean {
        return keys == null && !overflow && !attempted && !onPage && !running &&
            !extraInFlight && used < 8;
    }
}
