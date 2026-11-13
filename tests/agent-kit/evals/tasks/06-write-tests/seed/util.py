"""Numeric helpers."""


def clamp(value, low, high):
    """Return value limited to the range low..high."""
    return max(low, min(high, value))
