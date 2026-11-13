import os
import subprocess
import sys
import unittest

ENV = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", PYTHONIOENCODING="utf-8")

# Outputs recorded from the seed implementation.
CASES = [
    ("", b"0 lines, 0 words, 0 chars\n"),
    ("a b\nc\n", b"2 lines, 3 words, 6 chars\n"),
    ("one two", b"0 lines, 2 words, 7 chars\n"),
    ("  \n\n", b"2 lines, 0 words, 4 chars\n"),
    ("héllo\n", b"1 lines, 1 words, 6 chars\n"),
]


class HiddenPlain(unittest.TestCase):
    def test_plain_output_byte_identical(self):
        for text, want in CASES:
            with self.subTest(text=text):
                r = subprocess.run(
                    [sys.executable, "-B", "-m", "wordcount"],
                    input=text.encode("utf-8"), capture_output=True, env=ENV,
                )
                self.assertEqual(r.returncode, 0)
                self.assertEqual(r.stdout, want)
