import io
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

from wordcount.cli import main


class CliTest(unittest.TestCase):
    def test_file_argument(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "in.txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("a b\nc\n")
            out = io.StringIO()
            with redirect_stdout(out):
                rc = main([path])
        self.assertEqual(rc, 0)
        self.assertEqual(out.getvalue(), "2 lines, 3 words, 6 chars\n")

    def test_stdin(self):
        out = io.StringIO()
        with mock.patch("sys.stdin", io.StringIO("hello world\n")):
            with redirect_stdout(out):
                main([])
        self.assertEqual(out.getvalue(), "1 lines, 2 words, 12 chars\n")
