#!/usr/bin/env python3
"""No SDK, device, display or network access required."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import socket

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("parser", HERE / "parse.py")
parser = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parser)
stage_spec = importlib.util.spec_from_file_location("stager", HERE / "stage.py")
stager = importlib.util.module_from_spec(stage_spec)
stage_spec.loader.exec_module(stager)


class ParserTests(unittest.TestCase):
    def test_real_sample(self):
        self.assertEqual(parser.parse((HERE / "fixtures/real-pass.txt").read_text()),
                         (True, "passed=27 failed=0 errors=0"))

    def test_edge_cases(self):
        for text in ("", "garbled", "FAILED (passed=1, failed=0, errors=0)",
                     "PASSED (passed=0, failed=0, errors=0)",
                     "PASSED (passed=1, failed=1, errors=0)",
                     "PASSED (passed=1, failed=0, errors=1)",
                     "PASSED (passed=1, failed=0, errors=0)\nFAILED (passed=1, failed=1, errors=0)"):
            with self.subTest(text=text):
                self.assertFalse(parser.parse(text)[0])
        self.assertTrue(parser.parse("noise\r\nPASSED (passed=2, failed=0, errors=0)\r\n")[0])


class StageTests(unittest.TestCase):
    def test_secret_excluded_before_copy(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            dest = Path(tmp) / "stage"
            (root / "resources/strings").mkdir(parents=True)
            dest.mkdir()
            source = root / "resources/strings/secrets.xml"
            source.write_text("fixture-only-private-value")
            (root / "resources/strings/secrets.xml.template").write_text(
                '<strings><string id="SubscriptionKey"></string></strings>')
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            subprocess.run(["git", "-C", str(root), "add", "."], check=True)
            stager.stage(root, dest)
            self.assertNotIn("fixture-only-private-value",
                             (dest / "resources/strings/secrets.xml").read_text())
            self.assertEqual(source.read_text(), "fixture-only-private-value")


class FakeRunnerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        scratch = self.home / "scratch"
        scratch.mkdir()
        self.sdk = self.home / "sdk"
        (self.sdk / "bin").mkdir(parents=True)
        devices = self.home / "Devices"
        for name in ("fenix5", "descentg1", "descentmk343mm", "descentmk351mm",
                     "epix2", "instinct2", "instinct2s", "instinct2x"):
            (devices / name).mkdir(parents=True)
        self.env = dict(os.environ, CONNECT_IQ_DEVICES=str(devices),
                        TMPDIR=str(scratch), DISPLAY=":fake")
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            self.port = sock.getsockname()[1]
        self.write("monkeyc", '#!/bin/sh\nif [ "$1" = -v ]; then echo "Fake SDK"; exit; fi\n'
                   'while [ "$1" != -o ]; do shift; done\nshift\n: > "$1"\n')
        self.write("monkeydo", '#!/bin/sh\nprintf "PASSED (passed=1, failed=0, errors=0)\\n"\n')
        self.write("simulator", '#!/bin/sh\nexit 1\n')

    def write(self, name, content):
        file = self.sdk / "bin" / name
        file.write_text(content)
        file.chmod(0o755)

    def run_runner(self, *args):
        return subprocess.run(["bash", str(HERE / "run.sh"), "--sdk", str(self.sdk),
                               "--simulator-port", str(self.port),
                               "--startup-timeout", "1", "--run-timeout", "1",
                               *args, "fenix5"], env=self.env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)

    def test_compile_only(self):
        result = self.run_runner("--compile-only")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("tests=NOT RUN", result.stdout)
        self.assertFalse(list((self.home / "scratch").rglob("*.der")),
                         "temporary developer key was not cleaned up")

    def test_simulator_failure_and_cleanup(self):
        result = self.run_runner()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("simulator exited", result.stderr)

    def test_existing_listener_preserved_and_timeout_precedes_pass(self):
        # A fake server represents a pre-existing user simulator, not a Garmin run.
        server = subprocess.Popen(["python3", "-c",
            "import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);"
            f"s.bind(('127.0.0.1',{self.port})); s.listen(); time.sleep(12)"])
        self.addCleanup(lambda: (server.terminate(), server.wait()))
        import time
        for _ in range(40):
            with __import__("socket").socket() as sock:
                if sock.connect_ex(("127.0.0.1", self.port)) == 0:
                    break
            time.sleep(0.05)
        self.write("monkeydo", '#!/bin/sh\necho "PASSED (passed=1, failed=0, errors=0)"\nsleep 5\n')
        result = self.run_runner()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("monkeydo_exit=124", result.stdout)
        self.assertIsNone(server.poll(), "pre-existing listener was stopped")

    def test_missing_summary(self):
        self.write("monkeyc", '#!/bin/sh\nif [ "$1" = -v ]; then echo "Fake SDK"; else exit 1; fi\n')
        result = self.run_runner("--compile-only")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("compile=FAILED", result.stdout)

    def test_launch_error_overrides_pass(self):
        server = subprocess.Popen(["python3", "-c",
            "import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);"
            f"s.bind(('127.0.0.1',{self.port})); s.listen(); time.sleep(12)"])
        self.addCleanup(lambda: (server.terminate(), server.wait()))
        import time
        for _ in range(40):
            with socket.socket() as sock:
                if sock.connect_ex(("127.0.0.1", self.port)) == 0:
                    break
            time.sleep(0.05)
        self.write("monkeydo", '#!/bin/sh\necho "PASSED (passed=1, failed=0, errors=0)"\nexit 127\n')
        result = self.run_runner()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("monkeydo_exit=127", result.stdout)
        self.assertIsNone(server.poll())

    def test_malformed_result(self):
        server = subprocess.Popen(["python3", "-c",
            "import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);"
            f"s.bind(('127.0.0.1',{self.port})); s.listen(); time.sleep(12)"])
        self.addCleanup(lambda: (server.terminate(), server.wait()))
        import time
        for _ in range(40):
            with socket.socket() as sock:
                if sock.connect_ex(("127.0.0.1", self.port)) == 0:
                    break
            time.sleep(0.05)
        self.write("monkeydo", '#!/bin/sh\necho "Ran 0 tests"\n')
        result = self.run_runner()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing/malformed final summary", result.stdout)


if __name__ == "__main__":
    unittest.main()
