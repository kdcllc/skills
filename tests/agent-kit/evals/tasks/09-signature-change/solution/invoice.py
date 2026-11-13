"""Invoice text."""

from money import format_amount


def total_line(invoice):
    """invoice is a dict with "total" and "currency" keys."""
    return "Total: " + format_amount(invoice["total"], invoice["currency"])
