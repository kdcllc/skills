"""Money formatting."""


def format_amount(value):
    """Format value as dollars with thousands separators, e.g. $1,234.50."""
    return "$" + format(value, ",.2f")
