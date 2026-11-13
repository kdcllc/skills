"""Duration parsing. See SPEC.md for the full specification."""
import re

_UNITS = {"h": 3600, "m": 60, "s": 1}
_COMPONENT = re.compile(r"([0-9]+)([^0-9 \t]?)")
_MAX_SECONDS = 604800


def parse_duration(text):
    """Return the number of seconds in `text`."""
    if not isinstance(text, str):
        raise TypeError("duration must be a str, not %s" % type(text).__name__)
    body = text.strip(" \t")
    if not body:
        raise ValueError("empty duration")
    total = 0
    seen = set()
    pos = 0
    while pos < len(body):
        match = _COMPONENT.match(body, pos)
        if match is None or match.group(2) not in _UNITS or match.group(2) in seen:
            raise ValueError("invalid duration: %r" % (text,))
        number, unit = match.groups()
        seen.add(unit)
        total += int(number) * _UNITS[unit]
        pos = match.end()
        while pos < len(body) and body[pos] in " \t":
            pos += 1
    if total > _MAX_SECONDS:
        raise ValueError("duration exceeds one week: %r" % (text,))
    return total
