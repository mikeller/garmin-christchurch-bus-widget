import Toybox.Lang;

(:nearby)
class NearbyPageOrder {
    static const READY = 0;
    static const LOCATING = 1;
    static const UNAVAILABLE = 2;
    static const EMPTY = 3;

    // A null code identifies the status slot, never a real stop.
    static function build(favourites as Array<Number>, nearby as Array,
                          favouriteNearby as Array, before as Number,
                          state as Number) as Array {
        var ordered = NearbyStopMaths.buildPageOrder(favourites, nearby, favouriteNearby, before);
        if (state == READY && nearby.size() > 0) {
            return ordered;
        }
        var at = before < 0 ? 0 : before;
        if (at > favourites.size()) {
            at = favourites.size();
        }
        var withSlot = [] as Array;
        for (var i = 0; i <= ordered.size(); i++) {
            if (i == at) {
                withSlot.add([null, null, null, false] as Array);
            }
            if (i < ordered.size()) {
                withSlot.add(ordered[i]);
            }
        }
        return withSlot;
    }

    static function initialIndex(ordered as Array, favouriteCount as Number,
                                 before as Number) as Number {
        if (favouriteCount > 0 && before <= 0 && ordered.size() > 1 &&
            (ordered[0] as Array)[NearbyStopMaths.PAGE_CODE] == null) {
            return 1;
        }
        return 0;
    }

    static function selectedIndex(ordered as Array, selectedCode as Number?,
                                  oldIndex as Number, fallback as Number) as Number {
        if (selectedCode != null) {
            for (var i = 0; i < ordered.size(); i++) {
                if ((ordered[i] as Array)[NearbyStopMaths.PAGE_CODE] == selectedCode) {
                    return i;
                }
            }
        } else if (oldIndex >= 0 && oldIndex < ordered.size()) {
            // The slot either stays at this index or is replaced by the first
            // nearby page; never jump away from a favourite when rows insert.
            return oldIndex;
        }
        return fallback < ordered.size() ? fallback : 0;
    }

    static function nextIndex(index as Number, count as Number) as Number {
        return count == 0 ? 0 : (index + 1) % count;
    }
}
