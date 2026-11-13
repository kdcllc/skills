import json
import os
import subprocess
import sys
import tempfile
import unittest

PROJ = os.environ["PROJ_DIR"]
CLI = os.path.join(PROJ, "cli.py")


def run(path):
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    return subprocess.run(
        [sys.executable, "-B", CLI, path],
        capture_output=True,
        text=True,
        env=env,
        cwd=tempfile.gettempdir(),
    )


class CliCases(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def write(self, text):
        path = os.path.join(self.tmp.name, "c.json")
        with open(path, "w") as handle:
            handle.write(text)
        return path

    def assert_error(self, proc, code):
        self.assertEqual(proc.returncode, code, proc.stderr)
        self.assertTrue(proc.stderr.startswith("error:"), repr(proc.stderr))
        self.assertNotIn("Traceback", proc.stderr)
        lines = [ln for ln in proc.stderr.splitlines() if ln.strip()]
        self.assertEqual(len(lines), 1, repr(proc.stderr))
        self.assertEqual(proc.stdout, "")


class ValidTests(CliCases):
    def test_valid_config(self):
        proc = run(self.write(json.dumps({"name": "demo", "values": [1, 2, 3]})))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout, "demo: 3 values, total 6\n")
        self.assertEqual(proc.stderr, "")

    def test_valid_with_empty_values_and_extra_key(self):
        proc = run(self.write(json.dumps({"name": "e", "values": [], "extra": 1})))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout, "e: 0 values, total 0\n")


class FailureTests(CliCases):
    def test_missing_file(self):
        self.assert_error(run(os.path.join(self.tmp.name, "absent.json")), 2)

    def test_invalid_json(self):
        self.assert_error(run(self.write("{not json")), 3)

    def test_empty_file_is_invalid_json(self):
        self.assert_error(run(self.write("")), 3)

    def test_missing_name(self):
        self.assert_error(run(self.write(json.dumps({"values": [1]}))), 4)

    def test_missing_values(self):
        self.assert_error(run(self.write(json.dumps({"name": "x"}))), 4)


if __name__ == "__main__":
    unittest.main()
