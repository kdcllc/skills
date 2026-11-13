import io
import json
import os
import tempfile
import unittest
import warnings
from contextlib import redirect_stdout

from fetcher.cli import main
from fetcher.client import fetch
from fetcher.config import load_config


def write(tmp, data):
    path = os.path.join(tmp, "config.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle)
    return path


def load_recording(data):
    with tempfile.TemporaryDirectory() as tmp:
        path = write(tmp, data)
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            cfg = load_config(path)
    return cfg, [w for w in caught if issubclass(w.category, DeprecationWarning)]


class HiddenOldKey(unittest.TestCase):
    def test_old_key_loads_with_warning(self):
        cfg, warned = load_recording({"timeout": 7, "retries": 1})
        self.assertEqual(cfg["timeout_s"], 7)
        self.assertEqual(cfg["retries"], 1)
        self.assertNotIn("timeout", cfg)
        self.assertEqual(len(warned), 1)

    def test_old_key_zero_value(self):
        cfg, warned = load_recording({"timeout": 0})
        self.assertEqual(cfg["timeout_s"], 0)
        self.assertEqual(len(warned), 1)

    def test_both_keys_new_wins(self):
        cfg, _ = load_recording({"timeout": 7, "timeout_s": 9})
        self.assertEqual(cfg["timeout_s"], 9)
        self.assertNotIn("timeout", cfg)


class HiddenNewKey(unittest.TestCase):
    def test_new_key_loads_without_warning(self):
        cfg, warned = load_recording({"timeout_s": 5})
        self.assertEqual(cfg["timeout_s"], 5)
        self.assertEqual(warned, [])

    def test_default_without_warning(self):
        cfg, warned = load_recording({})
        self.assertEqual(cfg["timeout_s"], 30)
        self.assertEqual(cfg["retries"], 3)
        self.assertEqual(warned, [])

    def test_fetch_and_cli_use_new_key(self):
        self.assertEqual(
            fetch({"timeout_s": 5, "retries": 1}, "http://x/"),
            "GET http://x/ (timeout 5s, retries 1)",
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = write(tmp, {"timeout_s": 8})
            out = io.StringIO()
            with redirect_stdout(out):
                rc = main([path, "http://y/"])
        self.assertEqual(rc, 0)
        self.assertEqual(out.getvalue(), "GET http://y/ (timeout 8s, retries 3)\n")

    def test_cli_with_old_key_still_works(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write(tmp, {"timeout": 4})
            out = io.StringIO()
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", DeprecationWarning)
                with redirect_stdout(out):
                    rc = main([path, "http://z/"])
        self.assertEqual(rc, 0)
        self.assertEqual(out.getvalue(), "GET http://z/ (timeout 4s, retries 3)\n")
