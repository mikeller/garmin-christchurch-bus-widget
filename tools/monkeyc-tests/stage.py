#!/usr/bin/env python3
"""Copy tracked application sources without ever opening the local secret."""
import pathlib
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET


def stage(root, destination):
    paths = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "-z", "--cached"]
    ).split(b"\0")
    for raw in paths:
        if not raw:
            continue
        relative = pathlib.Path(raw.decode("utf-8"))
        if relative == pathlib.Path("resources/strings/secrets.xml"):
            continue
        source = root / relative
        if source.is_symlink():
            raise ValueError(f"refusing symlink in staged source: {relative}")
        if not source.is_file():
            raise ValueError(f"missing tracked file: {relative}")
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    template = destination / "resources/strings/secrets.xml.template"
    tree = ET.parse(template)
    strings = tree.getroot()
    if (strings.tag != "strings" or len(strings) != 1
            or strings[0].tag != "string"
            or strings[0].get("id") != "SubscriptionKey"
            or (strings[0].text or "").strip()):
        raise ValueError("template must contain only an empty SubscriptionKey")
    target = destination / "resources/strings/secrets.xml"
    target.write_bytes(template.read_bytes())


if __name__ == "__main__":
    try:
        stage(pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]))
    except (OSError, ValueError, subprocess.CalledProcessError, ET.ParseError) as error:
        sys.exit(f"staging failed: {error}")
