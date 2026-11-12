"""Unit tests for deploy_decision.py (standard library only).

Run with: python3 -m unittest discover tools/stoptiles
"""

import contextlib
import io
import json
import os
import tempfile
import unittest
import zipfile

import deploy_decision as dd
from generate_tiles import GENERATOR_VERSION

ETAG = 'W/"6213561-1794444360000"'
GV = GENERATOR_VERSION


def meta(n=2083, h="a" * 64, gv=GV, e=ETAG):
    return {"v": 1, "g": "2026-11-12", "gv": gv, "n": n, "h": h, "e": e,
            "attribution": "x"}


class PlanFetchTest(unittest.TestCase):
    def test_first_deploy_is_unconditional(self):
        self.assertEqual(dd.plan_fetch(None, False),
                         (False, "", "no-deployed-meta"))

    def test_deployed_etag_is_sent(self):
        self.assertEqual(dd.plan_fetch(meta(), False),
                         (True, ETAG, "conditional"))

    def test_force_is_unconditional(self):
        self.assertEqual(dd.plan_fetch(meta(), True), (False, "", "force"))

    def test_generator_version_change_is_unconditional(self):
        self.assertEqual(dd.plan_fetch(meta(gv=GV - 1), False),
                         (False, "", "generator-version-changed"))
        self.assertEqual(dd.plan_fetch(meta(gv=GV + 1), False),
                         (False, "", "generator-version-changed"))

    def test_missing_gv_is_unconditional(self):
        deployed = meta()
        del deployed["gv"]
        self.assertFalse(dd.plan_fetch(deployed, False)[0])

    def test_missing_or_empty_etag_is_unconditional(self):
        self.assertEqual(dd.plan_fetch(meta(e=""), False),
                         (False, "", "no-deployed-etag"))
        deployed = meta()
        del deployed["e"]
        self.assertEqual(dd.plan_fetch(deployed, False),
                         (False, "", "no-deployed-etag"))
        self.assertEqual(dd.plan_fetch(meta(e=None), False),
                         (False, "", "no-deployed-etag"))

    def test_malformed_etag_is_never_sent(self):
        for bad in ('no-quotes', 'W/"a"\r\nX-Evil: 1', '"a"b"', 'W/"a b"'):
            self.assertEqual(dd.plan_fetch(meta(e=bad), False),
                             (False, "", "invalid-deployed-etag"), bad)

    def test_strong_etag_is_accepted(self):
        self.assertEqual(dd.plan_fetch(meta(e='"abc123"'), False)[1], '"abc123"')


class ClassifyTest(unittest.TestCase):
    def test_deployed_meta_status(self):
        self.assertEqual(dd.classify_deployed(200), "present")
        self.assertEqual(dd.classify_deployed(404), "absent")
        for code in (301, 403, 500, 503):
            with self.assertRaises(dd.DecisionError):
                dd.classify_deployed(code)

    def test_fetch_304_only_when_conditional(self):
        self.assertEqual(dd.classify_fetch(304, True), "unchanged")
        with self.assertRaises(dd.DecisionError):
            dd.classify_fetch(304, False)

    def test_fetch_200_requires_zip(self):
        with tempfile.TemporaryDirectory() as tmp:
            good = os.path.join(tmp, "good.zip")
            with zipfile.ZipFile(good, "w") as archive:
                archive.writestr("stops.txt", "x")
            bad = os.path.join(tmp, "bad.zip")
            with open(bad, "w") as handle:
                handle.write('{"error":"quota"}')
            self.assertEqual(dd.classify_fetch(200, False, good), "download")
            self.assertEqual(dd.classify_fetch(200, True, good), "download")
            self.assertEqual(dd.classify_fetch(200, False), "download")
            with self.assertRaises(dd.DecisionError):
                dd.classify_fetch(200, False, bad)

    def test_fetch_other_codes_fail(self):
        for code in (0, 204, 301, 302, 401, 404, 429, 500):
            for conditional in (False, True):
                with self.assertRaises(dd.DecisionError, msg=str(code)):
                    dd.classify_fetch(code, conditional)


class EtagTest(unittest.TestCase):
    def test_extracts_etag_case_insensitively(self):
        text = ("HTTP/2 200 \r\ncontent-type: application/zip\r\n"
                'etag: W/"6213561-1794444360000"\r\n'
                "last-modified: Thu, 12 Nov 2026 00:46:00 GMT\r\n\r\n")
        self.assertEqual(dd.extract_etag(text), 'W/"6213561-1794444360000"')

    def test_last_response_block_wins(self):
        text = ('HTTP/1.1 503 Service Unavailable\r\nETag: "old"\r\n\r\n'
                "HTTP/1.1 200 OK\r\nContent-Type: application/zip\r\n\r\n")
        self.assertEqual(dd.extract_etag(text), "")

    def test_missing_or_malformed_etag_is_empty(self):
        self.assertEqual(dd.extract_etag("HTTP/2 200\r\nx: y\r\n"), "")
        self.assertEqual(dd.extract_etag("HTTP/2 200\r\nETag: nonsense\r\n"), "")
        self.assertEqual(dd.extract_etag(""), "")


class DecideTest(unittest.TestCase):
    def test_first_deploy(self):
        self.assertEqual(dd.decide(meta(), None, False), (True, "first-deploy"))

    def test_first_deploy_still_needs_the_floor(self):
        with self.assertRaises(dd.DecisionError):
            dd.decide(meta(n=1799), None, False)
        self.assertEqual(dd.decide(meta(n=1800), None, False),
                         (True, "first-deploy"))

    def test_unchanged_skips(self):
        self.assertEqual(dd.decide(meta(), meta(), False), (False, "unchanged"))

    def test_force_overrides_unchanged(self):
        self.assertEqual(dd.decide(meta(), meta(), True), (True, "force"))

    def test_changed_hash_deploys(self):
        self.assertEqual(dd.decide(meta(h="b" * 64), meta(), False),
                         (True, "stop-data-changed"))

    def test_generator_version_change_deploys_with_same_hash(self):
        self.assertEqual(dd.decide(meta(gv=GV + 1), meta(gv=GV), False),
                         (True, "generator-version-changed"))

    def test_etag_difference_alone_does_not_deploy(self):
        self.assertEqual(dd.decide(meta(e='W/"1-2"'), meta(), False),
                         (False, "unchanged"))

    def test_drop_exactly_at_threshold_is_allowed(self):
        deployed = meta(n=2000)
        self.assertEqual(dd.decide(meta(n=1800, h="b" * 64), deployed, False,
                                   min_stops="0"),
                         (True, "stop-data-changed"))

    def test_drop_beyond_threshold_fails(self):
        with self.assertRaises(dd.DecisionError) as ctx:
            dd.decide(meta(n=1799, h="b" * 64), meta(n=2000), False, min_stops="0")
        self.assertIn("fell from 2000 to 1799", str(ctx.exception))

    def test_drop_failure_is_not_overridden_by_force(self):
        with self.assertRaises(dd.DecisionError):
            dd.decide(meta(n=1500, h="b" * 64), meta(n=2083), True, min_stops="0")

    def test_drop_check_applies_even_when_hash_is_equal(self):
        with self.assertRaises(dd.DecisionError):
            dd.decide(meta(n=1000), meta(n=2000), False, min_stops="0")

    def test_growth_is_fine(self):
        self.assertEqual(dd.decide(meta(n=3000, h="b" * 64), meta(n=2083), False),
                         (True, "stop-data-changed"))

    def test_fractional_and_custom_percentage(self):
        deployed = meta(n=1000)
        self.assertEqual(dd.decide(meta(n=995, h="b" * 64), deployed, False,
                                   max_drop_percent="0.5", min_stops="0")[0], True)
        with self.assertRaises(dd.DecisionError):
            dd.decide(meta(n=994, h="b" * 64), deployed, False,
                      max_drop_percent="0.5", min_stops="0")
        with self.assertRaises(dd.DecisionError):
            dd.decide(meta(n=999, h="b" * 64), deployed, False,
                      max_drop_percent="0", min_stops="0")

    def test_absolute_floor(self):
        with self.assertRaises(dd.DecisionError) as ctx:
            dd.decide(meta(n=1799), meta(n=1799), False)
        self.assertIn("below the floor of 1800", str(ctx.exception))
        self.assertEqual(dd.decide(meta(n=1800), meta(n=1800), False),
                         (False, "unchanged"))
        self.assertEqual(dd.decide(meta(n=500, h="b" * 64), meta(n=520), False,
                                   min_stops="500")[0], True)

    def test_unusable_deployed_baseline_uses_floor_only(self):
        deployed = meta()
        del deployed["n"]
        self.assertEqual(dd.decide(meta(n=1900, h="b" * 64), deployed, False),
                         (True, "stop-data-changed"))
        with self.assertRaises(dd.DecisionError):
            dd.decide(meta(n=10), deployed, False)

    def test_invalid_thresholds_fail(self):
        for percent, floor in (("abc", "1"), ("-1", "1"), ("101", "1"),
                               ("10", "-1"), ("10", "x"), ("10", "1.5"),
                               ("1/0", "1")):
            with self.assertRaises(dd.DecisionError, msg=(percent, floor)):
                dd.decide(meta(), meta(), False, percent, floor)


class CliTest(unittest.TestCase):
    def run_cli(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = dd.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def write(self, tmp, name, obj):
        path = os.path.join(tmp, name)
        with open(path, "w", encoding="utf-8") as handle:
            if isinstance(obj, str):
                handle.write(obj)
            else:
                json.dump(obj, handle)
        return path

    def test_plan_fetch_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            deployed = self.write(tmp, "deployed.json", meta())
            code, out, _ = self.run_cli("plan-fetch", "--deployed", deployed)
            self.assertEqual(code, 0)
            self.assertEqual(out.splitlines(),
                             ["mode=conditional", "if_none_match=" + ETAG])
            code, out, _ = self.run_cli("plan-fetch", "--deployed", deployed,
                                        "--force", "true")
            self.assertEqual(out.splitlines(), ["mode=unconditional", "if_none_match="])
            code, out, _ = self.run_cli("plan-fetch", "--deployed",
                                        os.path.join(tmp, "absent.json"))
            self.assertEqual(out.splitlines(), ["mode=unconditional", "if_none_match="])

    def test_unparseable_deployed_meta_is_a_warning(self):
        with tempfile.TemporaryDirectory() as tmp:
            deployed = self.write(tmp, "deployed.json", "<html>")
            code, out, err = self.run_cli("plan-fetch", "--deployed", deployed)
            self.assertEqual(code, 0)
            self.assertIn("mode=unconditional", out)
            self.assertIn("no baseline", err)

    def test_decide_outputs_and_exit_codes(self):
        with tempfile.TemporaryDirectory() as tmp:
            new = self.write(tmp, "new.json", meta())
            deployed = self.write(tmp, "deployed.json", meta())
            code, out, _ = self.run_cli("decide", "--new", new, "--deployed", deployed)
            self.assertEqual((code, out.splitlines()),
                             (0, ["deploy=false", "reason=unchanged"]))
            code, out, _ = self.run_cli("decide", "--new", new, "--deployed", deployed,
                                        "--force", "true")
            self.assertEqual((code, out.splitlines()),
                             (0, ["deploy=true", "reason=force"]))
            small = self.write(tmp, "small.json", meta(n=10))
            code, out, err = self.run_cli("decide", "--new", small,
                                          "--deployed", os.path.join(tmp, "none"))
            self.assertEqual((code, out), (1, ""))
            self.assertIn("below the floor", err)

    def test_decide_rejects_broken_new_meta(self):
        with tempfile.TemporaryDirectory() as tmp:
            new = self.write(tmp, "new.json", {"n": "many"})
            code, _, err = self.run_cli("decide", "--new", new,
                                        "--deployed", os.path.join(tmp, "none"))
            self.assertEqual(code, 1)
            self.assertIn("new meta.json", err)

    def test_etag_and_classify_commands(self):
        with tempfile.TemporaryDirectory() as tmp:
            headers = self.write(tmp, "h.txt", 'HTTP/2 200\r\nETag: "x"\r\n\r\n')
            code, out, _ = self.run_cli("etag", headers)
            self.assertEqual((code, out), (0, 'etag="x"\n'))
            self.assertEqual(self.run_cli("classify-deployed", "--http-code", "404")[1],
                             "present=false\n")
            self.assertEqual(self.run_cli("classify-deployed", "--http-code", "200")[1],
                             "present=true\n")
            self.assertEqual(self.run_cli("classify-deployed", "--http-code", "500")[0], 1)
            self.assertEqual(self.run_cli("classify-fetch", "--http-code", "304",
                                          "--conditional", "true")[1],
                             "result=unchanged\n")
            self.assertEqual(self.run_cli("classify-fetch", "--http-code", "304",
                                          "--conditional", "false")[0], 1)


if __name__ == "__main__":
    unittest.main()
