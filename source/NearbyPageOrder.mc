import Toybox.Lang;

(:nearby)
class NearbyPageOrder {
    static const READY = 0;
    static const LOCATING = 1;
    static const UNAVAILABLE = 2;
    static const EMPTY = 3;
    static const WAITING_TILE = 4;

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
            NearbyWorkCount.iteration();
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

    // Select by identity, not the previous numerical index. A slot replaced
    // by a successful result becomes the first nearby page in the new list.
    static function preserve(oldPage as Dictionary?, newPages as Array<Dictionary>,
                             fallback as Number) as Number {
        if (oldPage != null) {
            var id = (oldPage as Dictionary)["stopId"] as Number?;
            for (var i = 0; i < newPages.size(); i++) {
                NearbyWorkCount.iteration();
                if (id != null && newPages[i]["stopId"] == id) {
                    return i;
                }
                if (id == null && newPages[i]["nearbySlot"] == true) {
                    return i;
                }
            }
            if (id == null) {
                for (var j = 0; j < newPages.size(); j++) {
                    NearbyWorkCount.iteration();
                    if (newPages[j]["nearby"] == true) {
                        return j;
                    }
                }
            } else if ((oldPage as Dictionary)["nearby"] == true) {
                // The selected nearby stop has left the live list. Start at
                // the first page, not the favourite just before Nearby.
                return 0;
            }
        }
        return fallback >= 0 && fallback < newPages.size() ? fallback : 0;
    }

    static function nextIndex(index as Number, count as Number) as Number {
        return count == 0 ? 0 : (index + 1) % count;
    }
}
