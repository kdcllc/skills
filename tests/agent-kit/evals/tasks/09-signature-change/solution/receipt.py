"""Receipt text."""

import money

RECEIPT_CURRENCY = "EUR"


def receipt_line(name, amount):
    return "%s: %s" % (name, money.format_amount(amount, RECEIPT_CURRENCY))
