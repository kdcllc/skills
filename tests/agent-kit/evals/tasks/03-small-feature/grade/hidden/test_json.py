import json
import os
import subprocess
import sys
import tempfile
import unittest

ENV = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", PYTHONIOENCODING="utf-8")


def run(args, text):
    r = subprocess.run(
        [sys.executable, "-B", "-m", "wordcount"] + args,
        input=text.encode("utf-8"), capture_output=True, env=ENV,
    )
    if r.stdout.endswith(b"\n"):  # one trailing newline is optional
        r.stdout = r.stdout[:-1]
    return r


class HiddenJson(unittest.TestCase):
    def test_exact_text_and_key_order(self):
        r = run(["--json"], "a b\nc\n")
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout, b'{"lines":2,"words":3,"chars":6}')
        self.assertEqual(list(json.loads(r.stdout)), ["lines", "words", "chars"])

    def test_empty_input(self):
        r = run(["--json"], "")
        self.assertEqual(r.stdout, b'{"lines":0,"words":0,"chars":0}')

    def test_no_trailing_newline_and_unicode(self):
        self.assertEqual(run(["--json"], "héllo wörld").stdout, b'{"lines":0,"words":2,"chars":11}')

    def test_file_argument_either_position(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "in.txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("x y z\n")
            for args in (["--json", path], [path, "--json"]):
                with self.subTest(args=args[0]):
                    self.assertEqual(run(args, "").stdout, b'{"lines":1,"words":3,"chars":6}')
