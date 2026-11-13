"""Unit tests for report_failure.py and keepalive.py (standard library only).

Neither test talks to GitHub: the ``gh`` calls are replaced by recorders.

Run with: python3 -m unittest discover tools/stoptiles
"""

import contextlib
import io
import json
import subprocess
import unittest
from unittest import mock

import keepalive
import report_failure as rf

RUN_URL = "https://github.com/octo/repo/actions/runs/42"


class Recorder:
    def __init__(self, open_issues):
        self.open_issues = open_issues
        self.calls = []

    def __call__(self, args, stdin=None):
        self.calls.append((args, stdin))
        if args[:2] == ["issue", "list"]:
            return json.dumps(self.open_issues)
        return ""


class BuildBodyTest(unittest.TestCase):
    def test_body_has_run_url_and_results(self):
        body = rf.build_body(RUN_URL, "schedule", "abc123", "refs/heads/master",
                             [("build", "success"), ("smoke-test", "failure")])
        self.assertIn(RUN_URL, body)
        self.assertIn("* `smoke-test`: failure", body)
        self.assertIn("* Event: `schedule`", body)
        self.assertTrue(body.endswith("\n"))

    def test_optional_fields_are_omitted(self):
        body = rf.build_body(RUN_URL, "", "", "", [])
        self.assertNotIn("Event", body)
        self.assertNotIn("Job results", body)

    def test_parse_results(self):
        self.assertEqual(rf.parse_results(["a=b", " c = failure "]),
                         [("a", "b"), ("c", "failure")])
        for bad in ("nope", "=x", "x="):
            with self.assertRaises(ValueError):
                rf.parse_results([bad])


class ReportTest(unittest.TestCase):
    def test_opens_an_issue_when_none_is_open(self):
        run = Recorder([{"number": 3, "title": "Something else"}])
        rf.report(rf.TITLE, "body", run=run, out=io.StringIO())
        self.assertEqual([c[0][:2] for c in run.calls],
                         [["issue", "list"], ["issue", "create"]])
        create = run.calls[1]
        self.assertEqual(create[0], ["issue", "create", "--title", rf.TITLE,
                                     "--body-file", "-"])
        self.assertEqual(create[1], "body")

    def test_comments_on_the_existing_open_issue(self):
        run = Recorder([{"number": 3, "title": "Something else"},
                        {"number": 9, "title": rf.TITLE},
                        {"number": 12, "title": rf.TITLE}])
        message = rf.report(rf.TITLE, "body", run=run, out=io.StringIO())
        self.assertEqual(message, "commented on issue #9")
        self.assertEqual(run.calls[1], (["issue", "comment", "9", "--body-file", "-"],
                                        "body"))

    def test_title_must_match_exactly(self):
        self.assertIsNone(rf.find_open_issue(
            [{"number": 1, "title": rf.TITLE + " (old)"},
             {"number": 2, "title": rf.TITLE.lower()}], rf.TITLE))

    def test_only_open_issues_are_requested(self):
        run = Recorder([])
        rf.report(rf.TITLE, "body", run=run, out=io.StringIO())
        self.assertIn("open", run.calls[0][0])

    def test_dry_run_never_runs_gh(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = rf.main(["--run-url", RUN_URL, "--result", "build=failure",
                            "--dry-run"])
        self.assertEqual(code, 0)
        self.assertIn("dry run", out.getvalue())
        self.assertIn(RUN_URL, out.getvalue())

    def test_gh_failure_fails_the_step(self):
        def fail(args, stdin=None):
            raise subprocess.CalledProcessError(1, ["gh"])
        err = io.StringIO()
        with mock.patch.object(rf, "gh", fail), contextlib.redirect_stderr(err):
            code = rf.main(["--run-url", RUN_URL])
        self.assertEqual(code, 1)
        self.assertIn("could not report the failure", err.getvalue())


class KeepaliveTest(unittest.TestCase):
    REF = "octo/repo/.github/workflows/stop-tiles.yml@refs/heads/master"

    def test_workflow_file_is_derived_from_the_ref(self):
        self.assertEqual(keepalive.workflow_file(self.REF, "octo/repo"),
                         "stop-tiles.yml")
        self.assertEqual(keepalive.workflow_file(self.REF, "Octo/Repo"),
                         "stop-tiles.yml")

    def test_foreign_or_malformed_refs_are_rejected(self):
        for ref in ("other/repo/.github/workflows/x.yml@refs/heads/master",
                    "octo/repo/.github/workflows/sub/x.yml@refs/heads/master",
                    "octo/repo/.github/workflows/x.txt@refs/heads/master",
                    "octo/repo/.github/workflows/../x.yml@refs/heads/master",
                    "", None):
            with self.assertRaises(keepalive.KeepaliveError, msg=ref):
                keepalive.workflow_file(ref, "octo/repo")
        with self.assertRaises(keepalive.KeepaliveError):
            keepalive.workflow_file(self.REF, "octo")

    def test_endpoint(self):
        self.assertEqual(keepalive.enable_endpoint("octo/repo", "stop-tiles.yml"),
                         "repos/octo/repo/actions/workflows/stop-tiles.yml/enable")

    def env(self):
        return {"GITHUB_WORKFLOW_REF": self.REF, "GITHUB_REPOSITORY": "octo/repo"}

    def test_main_calls_the_enable_endpoint(self):
        calls = []
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = keepalive.main([], self.env(), calls.append)
        self.assertEqual(code, 0)
        self.assertEqual(calls, [[
            "gh", "api", "--method", "PUT",
            "repos/octo/repo/actions/workflows/stop-tiles.yml/enable"]])

    def test_dry_run_makes_no_call(self):
        calls = []
        with contextlib.redirect_stdout(io.StringIO()):
            code = keepalive.main(["--dry-run"], self.env(), calls.append)
        self.assertEqual((code, calls), (0, []))

    def test_api_failure_fails_the_step(self):
        def run(command):
            raise subprocess.CalledProcessError(1, command)
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(keepalive.main([], self.env(), run), 1)

    def test_bad_environment_fails_without_a_call(self):
        calls = []
        with contextlib.redirect_stderr(io.StringIO()):
            code = keepalive.main([], {"GITHUB_REPOSITORY": "octo/repo"}, calls.append)
        self.assertEqual((code, calls), (1, []))


if __name__ == "__main__":
    unittest.main()
