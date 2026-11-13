#!/usr/bin/env python3
"""Open or update the GitHub issue that reports a failed stop tiles run.

Usage:
    report_failure.py --run-url URL [--event E] [--sha SHA] [--ref REF]
                      [--result JOB=RESULT ...] [--title T] [--dry-run]

The workflow calls this from a job that has ``issues: write`` and nothing
else that can write. It uses the ``gh`` CLI (authenticated through the
``GH_TOKEN`` and ``GH_REPO`` environment variables): if an open issue with
exactly the title already exists it receives a comment, otherwise a new issue
is opened. The issue is never closed automatically; a person closes it once
the cause is fixed. With ``--dry-run`` nothing is sent: the planned title and
body are printed and ``gh`` is not run at all.

Open issues are matched by exact title from ``gh issue list`` (not by the
search API, which is eventually consistent), looking at up to LIST_LIMIT open
issues.
"""

import argparse
import json
import subprocess
import sys

TITLE = "Stop tiles workflow failed"
LIST_LIMIT = 200


def build_body(run_url, event, sha, ref, results):
    lines = [
        "The scheduled `Stop tiles` workflow failed, so the published "
        "stop tiles for \"Departures near me\" may be stale or missing.",
        "",
        "* Run: %s" % run_url,
    ]
    if event:
        lines.append("* Event: `%s`" % event)
    if ref:
        lines.append("* Ref: `%s`" % ref)
    if sha:
        lines.append("* Commit: `%s`" % sha)
    if results:
        lines += ["", "Job results:", ""]
        lines += ["* `%s`: %s" % (name, result) for name, result in results]
    lines += [
        "",
        "Open the run, read the failed job's log, fix the cause, then re-run "
        "the workflow or wait for the next scheduled run. Close this issue "
        "once the workflow is green again. Later failures are added to this "
        "issue as comments while it stays open.",
    ]
    return "\n".join(lines) + "\n"


def parse_results(items):
    results = []
    for item in items or []:
        name, sep, result = item.partition("=")
        if not sep or not name.strip() or not result.strip():
            raise ValueError("--result must be JOB=RESULT, got %r" % item)
        results.append((name.strip(), result.strip()))
    return results


def find_open_issue(issues, title):
    """Number of the first open issue whose title equals title, else None."""
    for issue in issues:
        if issue.get("title") == title and isinstance(issue.get("number"), int):
            return issue["number"]
    return None


def gh(args, stdin=None):
    return subprocess.run(["gh"] + args, input=stdin, check=True, text=True,
                          stdout=subprocess.PIPE).stdout


def report(title, body, run=None, out=None):
    """Comment on the open issue or open a new one. Returns a description."""
    run = run or gh
    out = out or sys.stdout
    listing = run(["issue", "list", "--state", "open", "--limit", str(LIST_LIMIT),
                   "--json", "number,title"])
    number = find_open_issue(json.loads(listing or "[]"), title)
    if number is not None:
        run(["issue", "comment", str(number), "--body-file", "-"], stdin=body)
        message = "commented on issue #%d" % number
    else:
        run(["issue", "create", "--title", title, "--body-file", "-"], stdin=body)
        message = "opened a new issue"
    print(message, file=out)
    return message


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--run-url", required=True)
    parser.add_argument("--event", default="")
    parser.add_argument("--sha", default="")
    parser.add_argument("--ref", default="")
    parser.add_argument("--result", action="append", default=[],
                        help="JOB=RESULT, repeatable")
    parser.add_argument("--title", default=TITLE)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    try:
        body = build_body(args.run_url, args.event, args.sha, args.ref,
                          parse_results(args.result))
    except ValueError as error:
        parser.error(str(error))
    if args.dry_run:
        print("dry run: would open or update the issue %r with:\n\n%s"
              % (args.title, body))
        return 0
    try:
        report(args.title, body)
    except (subprocess.CalledProcessError, OSError, ValueError) as error:
        print("error: could not report the failure: %s" % error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
