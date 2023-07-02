import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:glance)
class Utils {
    // converts rfc3339 formatted timestamp to Time::Moment (null on error)
    // from https://forums.garmin.com/developer/connect-iq/f/discussion/2124/parsing-a-date-string-to-moment
    static function parseIsoDate(date as String?) as Moment? {
        // 0123456789012345678901234
        // 2011-10-17T13:00:00-07:00
        // 2011-10-17T16:30:55.000Z
        // 2011-10-17T16:30:55Z
        if (date == null || (date as String).length() < 20) {
            return null;
        }

        var moment = Gregorian.moment({
            :year => (date.substring( 0, 4) as String).toNumber(),
            :month => (date.substring( 5, 7) as String).toNumber(),
            :day => (date.substring( 8, 10) as String).toNumber(),
            :hour => (date.substring(11, 13) as String).toNumber(),
            :minute => (date.substring(14, 16) as String).toNumber(),
            :second => (date.substring(17, 19) as String).toNumber()
        });
        var suffix = date.substring(19, date.length()) as String;

        // skip over to time zone
        var tz = 0;
        if (".".equals(suffix.substring(tz, tz + 1))) {
            while (tz < suffix.length()) {
                var first = suffix.substring(tz, tz + 1) as String;
                if ("-+Z".find(first) != null) {
                    break;
                }
                tz++;
            }
        }

        if (tz >= suffix.length()) {
            // no timezone given
            return null;
        }

        var tzOffset = 0;
        if (!"Z".equals(suffix.substring(tz, tz + 1))) {
            // +HH:MM
            if (suffix.length() - tz < 6) {
                return null;
            }
            tzOffset = ((suffix.substring(tz + 1, tz + 3) as String).toNumber() as Number) * Gregorian.SECONDS_PER_HOUR;
            tzOffset += ((suffix.substring(tz + 4, tz + 6) as String).toNumber() as Number) * Gregorian.SECONDS_PER_MINUTE;

            var sign = suffix.substring(tz, tz + 1);
            if ("+".equals(sign)) {
                tzOffset = -tzOffset;
            } else if ("-".equals(sign) && tzOffset == 0) {
                // -00:00 denotes unknown timezone
                return null;
            }
        }

        return moment.add(new Time.Duration(tzOffset));
    }

    // Unfortunately this is not the inverse of parseIsoDate, as Moment does not keep track of the timezone
    static function dateToIsoString(date as Moment) as String {
        var dateInfo = Gregorian.info(date as Moment, Time.FORMAT_SHORT);
        return Lang.format("$1$-$2$-$3$T$4$:$5$:$6$-00:00", [
            dateInfo.year.format("%04d"),
            (dateInfo.month as Number).format("%02d"),
            dateInfo.day.format("%02d"),
            dateInfo.hour.format("%02d"),
            dateInfo.min.format("%02d"),
            dateInfo.sec.format("%02d"),
        ]);
    }

    static function locationToString(latitude as Float, longitude as Float) as String {
        return latitude.format("%.3f") + " " + longitude.format("%.3f");
    }

    static function log(message as String) as Void {
        System.println(Utils.dateToIsoString(Time.now()) + ": " + message);
    }
}