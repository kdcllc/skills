"""Money formatting."""


def format_amount(value, currency):
    """Format value as the currency code, a space and the amount, e.g. USD 1,234.50."""
    return currency + " " + format(value, ",.2f")
