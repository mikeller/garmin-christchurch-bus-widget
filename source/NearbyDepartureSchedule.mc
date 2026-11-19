import Toybox.Lang;

// Pure request order. Entries are [stop ID, favourite, last attempt time].
// Older attempts take precedence; favourites break ties. The visible stale
// page goes first. Proximity in cycling order breaks remaining ties.
(:nearby)
class NearbyDepartureSchedule {
    static function choose(entries as Array, current as Number, cap as Number,
                           inFlight as Array<Number>, currentStale as Boolean) as Array<Number> {
        var chosen = [] as Array<Number>;
        if (entries.size() == 0 || cap <= 0) {
            return chosen;
        }
        var used = [] as Array<Number>;
        if (currentStale && current >= 0 && current < entries.size() &&
            eligible(entries, current, inFlight, used)) {
            chosen.add(current);
            used.add(current);
        }
        while (chosen.size() < cap) {
            NearbyWorkCount.iteration();
            var best = -1;
            for (var step = 0; step < entries.size(); step++) {
                NearbyWorkCount.iteration();
                var index = (current + step) % entries.size();
                if (!eligible(entries, index, inFlight, used)) {
                    continue;
                }
                if (best < 0) {
                    best = index;
                    continue;
                }
                var entry = entries[index] as Array;
                var previous = entries[best] as Array;
                var age = entry[2] as Number;
                var previousAge = previous[2] as Number;
                if (age < previousAge ||
                    (age == previousAge && entry[1] == true && previous[1] != true)) {
                    best = index;
                }
            }
            if (best < 0) {
                break;
            }
            chosen.add(best);
            used.add(best);
        }
        return chosen;
    }

    private static function eligible(entries as Array, index as Number,
                                     inFlight as Array<Number>, used as Array<Number>) as Boolean {
        var entry = entries[index] as Array;
        var id = entry[0] as Number?;
        if (id == null) {
            return false;
        }
        for (var i = 0; i < inFlight.size(); i++) {
            NearbyWorkCount.iteration();
            if (inFlight[i] == id) {
                return false;
            }
        }
        for (var i = 0; i < used.size(); i++) {
            NearbyWorkCount.iteration();
            if (used[i] == index || (entries[used[i]] as Array)[0] == id) {
                return false;
            }
        }
        return true;
    }
}
