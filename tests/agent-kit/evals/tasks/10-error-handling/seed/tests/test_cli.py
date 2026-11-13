import contextlib
import io
import json
import os
import tempfile
import unittest

import cli


class CliTests(unittest.TestCase):
    def test_summarize(self):
        self.assertEqual(
            cli.summarize({"name": "demo", "values": [1, 2, 3]}),
            "demo: 3 values, total 6",
        )

    def test_main_prints_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "c.json")
            with open(path, "w") as handle:
                json.dump({"name": "x", "values": [2.5, 2.5]}, handle)
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = cli.main([path])
        self.assertEqual(code, 0)
        self.assertEqual(out.getvalue(), "x: 2 values, total 5.0\n")


if __name__ == "__main__":
    unittest.main()
