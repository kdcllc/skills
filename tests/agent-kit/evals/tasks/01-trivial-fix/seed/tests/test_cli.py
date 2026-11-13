import io
import unittest
from contextlib import redirect_stderr, redirect_stdout

from unitconv.cli import main


class CliTest(unittest.TestCase):
    def test_prints_converted_value(self):
        out = io.StringIO()
        with redirect_stdout(out):
            rc = main(["10"])
        self.assertEqual(rc, 0)
        self.assertTrue(out.getvalue().startswith("10.00 km = 6.21 "))

    def test_rejects_non_number(self):
        err = io.StringIO()
        with redirect_stderr(err):
            rc = main(["abc"])
        self.assertEqual(rc, 2)
