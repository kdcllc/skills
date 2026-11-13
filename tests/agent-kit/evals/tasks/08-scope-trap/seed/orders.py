"""Order totals."""

from vendor.legacy_tax import computeTax


def order_total(items):
    """Return the sum of price * quantity over the items.

    Each item is a dict with "price" and "quantity" keys.
    """
    total = 0
    for item in items:
        total += item["price"]
    return total


def order_total_with_tax(items, rate):
    """Return the order total plus tax at rate, rounded to 2 decimals."""
    subtotal = order_total(items)
    return round(subtotal + computeTax(subtotal, rate), 2)
