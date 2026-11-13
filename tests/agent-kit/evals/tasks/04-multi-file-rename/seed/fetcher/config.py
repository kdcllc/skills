"""Configuration loading for fetcher."""
import json

DEFAULTS = {"timeout": 30, "retries": 3}


def load_config(path):
    """Read a JSON config file and return a dict with every setting filled in."""
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    cfg = dict(DEFAULTS)
    cfg.update(data)
    return cfg
