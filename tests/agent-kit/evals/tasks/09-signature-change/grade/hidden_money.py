import inspect
import os
import sys
import unittest

sys.path.insert(0, os.environ["PROJ_DIR"])

import accounts  # noqa: E402
import invoice  # noqa: E402
import money  # noqa: E402
import receipt  # noqa: E402


class SignatureTests(unittest.TestCase):
    def test_currency_is_required_second_parameter(self):
        params = list(inspect.signature(money.format_amount).parameters.values())
        self.assertEqual([p.name for p in params], ["value", "currency"])
        self.assertIs(params[1].default, inspect.Parameter.empty)

    def test_call_without_currency_fails(self):
        with self.assertRaises(TypeError):
            money.format_amount(1)


class FormatTests(unittest.TestCase):
    def test_rule(self):
        self.assertEqual(money.format_amount(1234.5, "USD"), "USD 1,234.50")
        self.assertEqual(money.format_amount(0, "JPY"), "JPY 0.00")
        self.assertEqual(money.format_amount(1000000, "GBP"), "GBP 1,000,000.00")
        self.assertEqual(money.format_amount(-5, "EUR"), "EUR -5.00")


class CallerTests(unittest.TestCase):
    def test_invoice_uses_its_currency(self):
        for code, total, want in (
            ("USD", 1234.5, "Total: USD 1,234.50"),
            ("GBP", 1000000, "Total: GBP 1,000,000.00"),
            ("JPY", 0, "Total: JPY 0.00"),
        ):
            self.assertEqual(invoice.total_line({"total": total, "currency": code}), want)

    def test_account_uses_its_currency(self):
        acct = {"owner": "Bo", "balance": 2500.75, "currency": "CAD"}
        self.assertEqual(accounts.balance_label(acct), "Bo balance: CAD 2,500.75")
        acct = {"owner": "Cy", "balance": 0, "currency": "CHF"}
        self.assertEqual(accounts.balance_label(acct), "Cy balance: CHF 0.00")

    def test_receipt_uses_receipt_currency(self):
        self.assertEqual(receipt.RECEIPT_CURRENCY, "EUR")
        self.assertEqual(receipt.receipt_line("Coffee", 3.5), "Coffee: EUR 3.50")
        self.assertEqual(receipt.receipt_line("Cake", 12000), "Cake: EUR 12,000.00")


if __name__ == "__main__":
    unittest.main()
