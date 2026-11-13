"""Duration parsing. See SPEC.md for the full specification."""
import re

_UNITS = {"h": 3600, "m": 60, "s": 1}
_SINGLE = re.compile(r"([0-9]+)([hms])")


def parse_duration(text):
    """Return the number of seconds in `text` (a single component only for now)."""
    match = _SINGLE.fullmatch(text)
    if match is None:
        raise ValueError("invalid duration: %r" % (text,))
    return int(match.group(1)) * _UNITS[match.group(2)]
