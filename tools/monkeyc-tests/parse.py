#!/usr/bin/env python3
"""Strictly parse the last non-empty monkeydo result line."""
import re
import sys

SUMMARY = re.compile(r"(PASSED|FAILED) \(passed=(\d+), failed=(\d+), errors=(\d+)\)")


def parse(text):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    last = lines[-1] if lines else ""
    match = SUMMARY.fullmatch(last)
    if not match:
        return False, "missing/malformed final summary"
    verdict, passed, failed, errors = match.groups()
    result = f"passed={passed} failed={failed} errors={errors}"
    return verdict == "PASSED" and int(passed) > 0 and int(failed) == int(errors) == 0, result


if __name__ == "__main__":
    good, message = parse(open(sys.argv[1], encoding="utf-8", errors="replace").read())
    print(message)
    sys.exit(0 if good else 1)
