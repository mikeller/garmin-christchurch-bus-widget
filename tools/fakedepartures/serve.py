#!/usr/bin/env python3
"""Local, offline SIRI StopMonitoring fixture server for the Connect IQ simulator."""

import argparse
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys
import time
from urllib.parse import parse_qs, urlsplit


SCENARIOS = {
    "coverage": "Shared, opposite and short-turn journeys (90100-90104)",
    "normal": "3 to 5 upcoming departures (stop codes 90000-90009)",
    "busy": "32 departures, approximately 43 KB (90010)",
    "medium": "12 departures, approximately 16 KB (90011)",
    "empty": "No trips on stop., 324 bytes (90020)",
    "http401": "HTTP 401 (90031)",
    "http403": "HTTP 403 (90033)",
    "http500": "HTTP 500 (90050)",
    "http503": "HTTP 503 (90053)",
    "nonjson": "HTTP 200 non-JSON (90060)",
    "truncated": "HTTP 200 truncated JSON (90061)",
    "slow": "Delayed normal response (90070)",
    "malformed": "Visits missing destination, route or time (90080)",
}
STOPS = {
    "90100": "coverage", "90101": "coverage", "90102": "coverage",
    "90103": "coverage", "90104": "coverage",
    "90010": "busy", "90011": "medium", "90020": "empty",
    "90031": "http401", "90033": "http403", "90050": "http500",
    "90053": "http503", "90060": "nonjson", "90061": "truncated",
    "90070": "slow", "90080": "malformed",
}
DESTINATIONS = (
    "Lyttelton via Moorhouse Ave and Ferry Rd",
    "Airport via Papanui Rd and Memorial Ave",
    "Rāpaki (via Sumner)",
    "City", "New Brighton", "Cashmere (Hospital)",
)
ROUTES = ("8", "28", "100", "3", "5", "Orbiter")


def iso(moment):
    return moment.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def scenario_for(stopcode, default=None):
    return default or STOPS.get(stopcode, "normal")


def envelope(delivery, now):
    return {"Siri": {"ServiceDelivery": {
        "ResponseTimestamp": iso(now),
        "StopMonitoringDelivery": [delivery],
    }}}


def visit(index, stopcode, now, detailed=False):
    departure = now + timedelta(minutes=3 + index * 4)
    journey = {
        "PublishedLineName": ROUTES[index % len(ROUTES)],
        "DestinationName": DESTINATIONS[index % len(DESTINATIONS)],
        "MonitoredCall": {
            "StopPointName": "Bus Interchange (Platform 1)",
            "ExpectedDepartureTime": iso(departure),
            "VehicleAtStop": index == 0,
        },
    }
    if detailed:
        # Typical SIRI ancillary journey/call fields, ignored by the widget.
        # Stable fixture strings make large-response and parsing tests repeatable.
        journey.update({
            "LineRef": "Metro:Christchurch:" + str(index),
            "DirectionRef": "Outbound",
            "OperatorRef": "Metro",
            "VehicleRef": "vehicle-" + str(index),
            "OriginName": "Christchurch Bus Interchange",
            "DestinationRef": "destination-" + str(index),
            "FramedVehicleJourneyRef": {
                "DataFrameRef": now.strftime("%Y-%m-%d"),
                "DatedVehicleJourneyRef": "journey-" + str(index),
            },
            "SituationRef": ["fixture-" + str(index)],
            "JourneyNote": "Simulator fixture only. " + ("Bus interchange service information. " * 10),
        })
        journey["MonitoredCall"].update({
            "StopPointRef": stopcode,
            "AimedDepartureTime": iso(departure - timedelta(minutes=1)),
            "ExpectedArrivalTime": iso(departure - timedelta(minutes=1)),
            "AimedArrivalTime": iso(departure - timedelta(minutes=2)),
            "VisitNumber": 1,
            "PlatformName": "Platform 1",
            "ArrivalStatus": "onTime",
            "DepartureStatus": "onTime",
            "StopNote": "Simulator fixture only. " + ("Platform information. " * 5),
        })
    return {"MonitoredVehicleJourney": journey}


def json_bytes(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def response(scenario, stopcode, now=None):
    """Return (status, content type, body). Inject now for deterministic tests."""
    if scenario not in SCENARIOS:
        raise ValueError("Unknown scenario: " + scenario)
    now = now or datetime.now(timezone.utc)
    if scenario.startswith("http"):
        status = int(scenario[4:])
        return status, "text/plain; charset=utf-8", ("Fixture HTTP " + str(status)).encode()
    if scenario == "nonjson":
        return 200, "text/plain; charset=utf-8", b"This is not JSON."
    if scenario == "truncated":
        return 200, "application/json; charset=utf-8", b'{"Siri":{"ServiceDelivery":{"StopMonitoringDelivery":['

    delivery = {"ValidUntil": iso(now + timedelta(minutes=2))}
    if scenario == "coverage":
        # Arrival times deliberately differ: dedupe compares line and full
        # destination, not vehicle, trip or timestamp. 90102 is opposite
        # direction, 90103 shares a line but short-turns, 90104 has a
        # previously unseen key among otherwise shared departures.
        journeys = {
            "90100": (("8", "City"), ("28", "Airport")),
            "90101": (("8", "City"), ("28", "Airport")),
            "90102": (("8", "Airport"),),
            "90103": (("8", "City"), ("8", "Hospital")),
            "90104": (("8", "City"), ("100", "Lyttelton")),
        }
        if stopcode not in journeys:
            raise ValueError("coverage scenario needs stop 90100-90104")
        visits = []
        for index, (line, destination) in enumerate(journeys[stopcode]):
            item = visit(index, stopcode, now)
            journey = item["MonitoredVehicleJourney"]
            journey["PublishedLineName"] = line
            journey["DestinationName"] = destination
            visits.append(item)
        delivery["MonitoredStopVisit"] = visits
        return 200, "application/json; charset=utf-8", json_bytes(envelope(delivery, now))
    if scenario == "empty":
        delivery["ErrorCondition"] = {"OtherError": {"ErrorText": "No trips on stop."}}
        body = json_bytes(envelope(delivery, now))
        # JSON whitespace keeps the syntactically valid error response at 324 bytes.
        assert len(body) <= 324
        return 200, "application/json; charset=utf-8", body + b" " * (324 - len(body))

    count = {"normal": 5, "busy": 32, "medium": 12, "slow": 5, "malformed": 3}[scenario]
    visits = [visit(i, stopcode, now, scenario in ("busy", "medium")) for i in range(count)]
    if scenario == "malformed":
        del visits[0]["MonitoredVehicleJourney"]["DestinationName"]
        del visits[1]["MonitoredVehicleJourney"]["PublishedLineName"]
        del visits[2]["MonitoredVehicleJourney"]["MonitoredCall"]["ExpectedDepartureTime"]
    delivery["MonitoredStopVisit"] = visits
    return 200, "application/json; charset=utf-8", json_bytes(envelope(delivery, now))


def tile_response(path, tiles_dir, scenario, delay):
    """Return a tile fixture response; never resolve paths outside tiles_dir."""
    if scenario == "slow":
        time.sleep(delay)
    if scenario == "http500":
        return 500, "text/plain; charset=utf-8", b"Fixture tile error"
    if scenario == "malformed":
        return 200, "application/json; charset=utf-8", b'{"s":['
    if scenario == "empty":
        return 200, "application/json; charset=utf-8", b'{"v":1,"s":[]}'
    parts = path.strip("/").split("/")
    if path == "/meta.json":
        relative = Path("meta.json")
    elif (len(parts) == 3 and parts[0] == "t" and parts[1].isdigit()
          and parts[2].endswith(".json") and parts[2][:-5].isdigit()):
        relative = Path(*parts)
    else:
        return 404, "text/plain; charset=utf-8", b"Not found"
    target = (tiles_dir / relative).resolve()
    if not target.is_relative_to(tiles_dir.resolve()) or not target.is_file():
        return 404, "text/plain; charset=utf-8", b"Not found"
    return 200, "application/json; charset=utf-8", target.read_bytes()


def make_handler(default_scenario=None, tiles_dir=None, delay=5.0):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urlsplit(self.path)
            # Do not log request headers, subscription keys, or arbitrary query text.
            params = parse_qs(parsed.query)
            override = params.get("scenario", [None])[0]
            if override is not None and override not in SCENARIOS:
                self.send_body(400, "text/plain; charset=utf-8", b"Unknown scenario")
                return
            if parsed.path in ("/rti/siri/v1/sm", "/sm"):
                stopcode = params.get("stopcode", [""])[0]
                if not stopcode.isdigit():
                    self.send_body(400, "text/plain; charset=utf-8", b"Missing numeric stopcode")
                    return
                chosen = override or scenario_for(stopcode, default_scenario)
                if chosen == "slow":
                    time.sleep(delay)
                status, content_type, body = response(chosen, stopcode)
            elif tiles_dir is not None and (parsed.path == "/meta.json" or parsed.path.startswith("/t/")):
                chosen = override or default_scenario
                status, content_type, body = tile_response(parsed.path, tiles_dir, chosen, delay)
            else:
                status, content_type, body = 404, "text/plain; charset=utf-8", b"Not found"
            self.send_body(status, content_type, body)

        def send_body(self, status, content_type, body):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def log_message(self, format, *args):
            # BaseHTTPRequestHandler's default logs the raw URL. Never do that.
            print("fixture %s %s %s" % (self.command, urlsplit(self.path).path, args[1]
                  if len(args) > 1 else ""), file=sys.stderr)

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--scenario", choices=SCENARIOS, help="force all stop requests to one scenario")
    parser.add_argument("--delay", type=float, default=5, help="slow response delay in seconds")
    parser.add_argument("--tiles-dir", type=Path, help="optional static tiles directory")
    parser.add_argument("--list-scenarios", action="store_true")
    args = parser.parse_args()
    if args.list_scenarios:
        for name, description in SCENARIOS.items():
            print("%-10s %s" % (name, description))
        return
    if args.delay < 0 or args.port < 0 or args.port > 65535:
        parser.error("delay must be non-negative and port must be 0-65535")
    if args.tiles_dir is not None and not args.tiles_dir.is_dir():
        parser.error("--tiles-dir must be an existing directory")
    server = ThreadingHTTPServer((args.host, args.port),
                                 make_handler(args.scenario, args.tiles_dir, args.delay))
    print("Fixture listening on %s:%s" % server.server_address, file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
