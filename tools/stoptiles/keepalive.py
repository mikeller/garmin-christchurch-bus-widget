#!/usr/bin/env python3
"""Re-enable this workflow so GitHub does not disable its schedule.

Usage:
    keepalive.py [--dry-run]

GitHub disables scheduled workflows in a public repository after 60 days
without repository activity. The workflow calls this from a scheduled-only job
that has ``actions: write`` and nothing else that can write. It calls the
REST endpoint ``PUT /repos/{owner}/{repo}/actions/workflows/{file}/enable``
through the ``gh`` CLI (``GH_TOKEN`` is the job's token). No commit is made.

The workflow file is derived from the ``GITHUB_WORKFLOW_REF`` and
``GITHUB_REPOSITORY`` environment variables, for example
``owner/repo/.github/workflows/stop-tiles.yml@refs/heads/master``. With
``--dry-run`` the call is printed and not made.

Whether enabling an already enabled workflow restarts GitHub's 60 day clock is
NOT documented by GitHub; see the header of the workflow file.
"""

import argparse
import os
import re
import subprocess
import sys

_NAME_RE = re.compile(r"[A-Za-z0-9._-]+\.ya?ml", re.ASCII)
_REPO_RE = re.compile(r"[A-Za-z0-9._-]+/[A-Za-z0-9._-]+", re.ASCII)


class KeepaliveError(Exception):
    """The environment does not describe a workflow file in this repository."""


def workflow_file(workflow_ref, repository):
    if not _REPO_RE.fullmatch(repository or ""):
        raise KeepaliveError("GITHUB_REPOSITORY is not owner/repo: %r" % repository)
    path = (workflow_ref or "").split("@", 1)[0]
    prefix = "%s/.github/workflows/" % repository
    if path[:len(prefix)].lower() != prefix.lower():
        raise KeepaliveError("GITHUB_WORKFLOW_REF is not a workflow file of %s: %r"
                             % (repository, workflow_ref))
    name = path[len(prefix):]
    if not _NAME_RE.fullmatch(name):
        raise KeepaliveError("unexpected workflow file name: %r" % name)
    return name


def enable_endpoint(repository, name):
    return "repos/%s/actions/workflows/%s/enable" % (repository, name)


def main(argv=None, environ=None, run=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    environ = os.environ if environ is None else environ
    run = run or (lambda command: subprocess.run(command, check=True))
    try:
        name = workflow_file(environ.get("GITHUB_WORKFLOW_REF"),
                             environ.get("GITHUB_REPOSITORY"))
    except KeepaliveError as error:
        print("error: %s" % error, file=sys.stderr)
        return 1
    command = ["gh", "api", "--method", "PUT",
               enable_endpoint(environ["GITHUB_REPOSITORY"], name)]
    if args.dry_run:
        print("dry run: would run: %s" % " ".join(command))
        return 0
    try:
        run(command)
    except (subprocess.CalledProcessError, OSError) as error:
        print("error: enabling %s failed: %s" % (name, error), file=sys.stderr)
        return 1
    print("re-enabled workflow %s (no commit made)" % name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
