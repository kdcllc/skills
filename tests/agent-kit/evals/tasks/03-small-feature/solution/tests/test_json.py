import io
import unittest
from contextlib import redirect_stdout
from unittest import mock

from wordcount.cli import main


class JsonTest(unittest.TestCase):
    def run_main(self, text, argv):
        out = io.StringIO()
        with mock.patch("sys.stdin", io.StringIO(text)):
            with redirect_stdout(out):
                main(argv)
        return out.getvalue()

    def test_json_shape(self):
        self.assertEqual(self.run_main("a b\nc\n", ["--json"]), '{"lines":2,"words":3,"chars":6}\n')

    def test_json_empty(self):
        self.assertEqual(self.run_main("", ["--json"]), '{"lines":0,"words":0,"chars":0}\n')
