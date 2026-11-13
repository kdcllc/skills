"""Account labels."""

from money import format_amount as fmt


def balance_label(account):
    """account is a dict with "owner", "balance" and "currency" keys."""
    return "%s balance: %s" % (account["owner"], fmt(account["balance"]))
