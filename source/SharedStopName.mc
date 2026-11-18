import Toybox.Lang;

// The departure reader needs this even where nearby pages are unavailable.
class SharedStopName {
    static function clean(name as String) as String {
        var pos = name.find(" near ");
        if (pos != null) {
            name = name.substring(0, pos);
        }
        pos = name.find("Bus ");
        if (pos != null) {
            name = name.substring(0, pos) + name.substring(pos + 4, name.length());
        }
        pos = name.find(" (Platform ");
        if (pos != null) {
            name = name.substring(0, pos + 2) + name.substring(pos + 11, name.length());
        }
        return name;
    }
}
