"""Configuration loading for fetcher."""
import json
import warnings

DEFAULTS = {"timeout_s": 30, "retries": 3}
_OLD_TIMEOUT_KEY = "timeout"


def load_config(path):
    """Read a JSON config file and return a dict with every setting filled in.

    The old `timeout` key is still accepted with a DeprecationWarning and is
    stored as `timeout_s`; if both are present, `timeout_s` wins.
    """
    with open(path, encoding="utf-8") as handle:
        data = dict(json.load(handle))
    if _OLD_TIMEOUT_KEY in data:
        warnings.warn(
            "config key 'timeout' is deprecated, use 'timeout_s'",
            DeprecationWarning,
            stacklevel=2,
        )
        old = data.pop(_OLD_TIMEOUT_KEY)
        data.setdefault("timeout_s", old)
    cfg = dict(DEFAULTS)
    cfg.update(data)
    return cfg
