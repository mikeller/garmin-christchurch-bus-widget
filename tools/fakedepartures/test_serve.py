"""Offline generator and HTTP contract tests."""

from datetime import datetime, timedelta, timezone
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import serve


NOW = datetime(2026, 11, 16, 23, 59, tzinfo=timezone.utc)


class GeneratorTests(unittest.TestCase):
    def delivery(self, scenario="normal"):
        body = serve.response(scenario, "90000", NOW)[2]
        return json.loads(body)["Siri"]["ServiceDelivery"]["StopMonitoringDelivery"][0]

    def test_required_fields_and_relative_times(self):
        delivery = self.delivery()
        self.assertEqual(delivery["ValidUntil"], serve.iso(NOW + timedelta(minutes=2)))
        visits = delivery["MonitoredStopVisit"]
        self.assertEqual(len(visits), 5)
        for index, visit in enumerate(visits):
            journey = visit["MonitoredVehicleJourney"]
            self.assertIsInstance(journey["PublishedLineName"], str)
            self.assertIsInstance(journey["DestinationName"], str)
            call = journey["MonitoredCall"]
            self.assertIsInstance(call["StopPointName"], str)
            self.assertIsInstance(call["VehicleAtStop"], bool)
            self.assertEqual(call["ExpectedDepartureTime"],
                             serve.iso(NOW + timedelta(minutes=3 + index * 4)))
        self.assertIn("Rāpaki", visits[2]["MonitoredVehicleJourney"]["DestinationName"])

    def test_busy_and_medium_sizes(self):
        for scenario, count, target in (("busy", 32, 43000), ("medium", 12, 16000)):
            body = serve.response(scenario, "90010", NOW)[2]
            self.assertEqual(len(json.loads(body)["Siri"]["ServiceDelivery"]
                                 ["StopMonitoringDelivery"][0]["MonitoredStopVisit"]), count)
            self.assertLessEqual(abs(len(body) - target), target * .10)

    def test_empty_body_and_error_shape(self):
        status, mime, body = serve.response("empty", "90020", NOW)
        self.assertEqual(status, 200)
        self.assertEqual(len(body), 324)
        self.assertEqual(json.loads(body)["Siri"]["ServiceDelivery"]
                         ["StopMonitoringDelivery"][0]["ErrorCondition"]
                         ["OtherError"]["ErrorText"], "No trips on stop.")

    def test_http_and_invalid_body_scenarios(self):
        for scenario, status in (("http401", 401), ("http403", 403),
                                 ("http500", 500), ("http503", 503)):
            self.assertEqual(serve.response(scenario, "90000", NOW)[0], status)
        for scenario in ("nonjson", "truncated"):
            with self.assertRaises(json.JSONDecodeError):
                json.loads(serve.response(scenario, "90000", NOW)[2])

    def test_malformed_fields(self):
        journeys = [v["MonitoredVehicleJourney"] for v in
                    self.delivery("malformed")["MonitoredStopVisit"]]
        self.assertNotIn("DestinationName", journeys[0])
        self.assertNotIn("PublishedLineName", journeys[1])
        self.assertNotIn("ExpectedDepartureTime", journeys[2]["MonitoredCall"])

    def test_stop_rules(self):
        self.assertEqual(serve.scenario_for("90103"), "coverage")
        self.assertEqual(serve.scenario_for("90010"), "busy")
        self.assertEqual(serve.scenario_for("90000"), "normal")
        self.assertEqual(serve.scenario_for("90010", "empty"), "empty")

    def test_multiple_stop_coverage(self):
        def keys(code):
            body = serve.response("coverage", code, NOW)[2]
            visits = json.loads(body)["Siri"]["ServiceDelivery"][
                "StopMonitoringDelivery"][0]["MonitoredStopVisit"]
            return {(v["MonitoredVehicleJourney"]["PublishedLineName"],
                     v["MonitoredVehicleJourney"]["DestinationName"]) for v in visits}

        near = keys("90100")
        self.assertEqual(near, keys("90101"))
        self.assertFalse(keys("90102") <= near, "opposite direction")
        self.assertFalse(keys("90103") <= near, "short turn")
        self.assertFalse(keys("90104") <= near, "new line among shared departures")


class HttpTests(unittest.TestCase):
    def setUp(self):
        self.tiles = tempfile.TemporaryDirectory()
        root = Path(self.tiles.name)
        (root / "t" / "100").mkdir(parents=True)
        (root / "t" / "100" / "200.json").write_text('{"v":1,"s":[[1,2,3,"Stop"]]}')
        (root / "meta.json").write_text('{"v":1}')
        self.server = ThreadingHTTPServer(("127.0.0.1", 0),
                                          serve.make_handler(tiles_dir=root, delay=0))
        self.thread = threading.Thread(target=self.server.serve_forever)
        self.thread.start()
        self.base = "http://127.0.0.1:%d" % self.server.server_port

    def tearDown(self):
        self.server.shutdown()
        self.thread.join()
        self.server.server_close()
        self.tiles.cleanup()

    def fetch(self, path):
        req = Request(self.base + path, headers={"Ocp-Apim-Subscription-Key": "must-not-log"})
        try:
            with urlopen(req) as reply:
                return reply.status, reply.read()
        except HTTPError as error:
            with error:
                return error.code, error.read()

    def test_real_path_and_alias(self):
        for path in ("/rti/siri/v1/sm?stopcode=90000", "/sm?stopcode=90000"):
            status, body = self.fetch(path)
            self.assertEqual(status, 200)
            self.assertEqual(len(json.loads(body)["Siri"]["ServiceDelivery"]
                                  ["StopMonitoringDelivery"][0]["MonitoredStopVisit"]), 5)

    def test_multiple_stops_and_failure_shapes(self):
        for code in ("90100", "90101", "90102", "90103", "90104"):
            self.assertEqual(self.fetch("/sm?stopcode=" + code)[0], 200)
        for code in ("90020", "90070", "90080"):
            self.assertEqual(self.fetch("/sm?stopcode=" + code)[0], 200)
        self.assertEqual(self.fetch("/sm?stopcode=90061")[0], 200)

    def test_override_and_errors(self):
        self.assertEqual(len(self.fetch("/sm?stopcode=90000&scenario=empty")[1]), 324)
        self.assertEqual(self.fetch("/sm?stopcode=90031")[0], 401)
        self.assertEqual(self.fetch("/sm?stopcode=90000&scenario=bad")[0], 400)
        self.assertEqual(self.fetch("/sm")[0], 400)

    def test_tile_static_and_failures(self):
        for path in ("/meta.json", "/t/100/200.json"):
            self.assertEqual(self.fetch(path)[0], 200)
        self.assertEqual(json.loads(self.fetch("/t/100/200.json?scenario=empty")[1])["s"], [])
        self.assertEqual(self.fetch("/t/100/201.json")[0], 404)
        self.assertEqual(self.fetch("/t/100/200.json?scenario=http500")[0], 500)
        with self.assertRaises(json.JSONDecodeError):
            json.loads(self.fetch("/t/100/200.json?scenario=malformed")[1])
        self.assertEqual(self.fetch("/t/100/200.json?scenario=slow")[0], 200)

    def test_unlisted_path(self):
        self.assertEqual(self.fetch("/secret")[0], 404)


if __name__ == "__main__":
    unittest.main()
