import json
import os
import tempfile
import unittest

from fetcher.config import load_config


def write(tmp, data):
    path = os.path.join(tmp, "config.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle)
    return path


class ConfigTest(unittest.TestCase):
    def test_defaults(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = load_config(write(tmp, {}))
        self.assertEqual(cfg["timeout"], 30)
        self.assertEqual(cfg["retries"], 3)

    def test_override(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = load_config(write(tmp, {"timeout": 5}))
        self.assertEqual(cfg["timeout"], 5)
