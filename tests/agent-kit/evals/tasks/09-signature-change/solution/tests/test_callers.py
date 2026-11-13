import unittest

from accounts import balance_label
from invoice import total_line
from receipt import receipt_line


class CallerTests(unittest.TestCase):
    def test_invoice(self):
        self.assertEqual(total_line({"total": 99, "currency": "USD"}), "Total: USD 99.00")

    def test_receipt(self):
        self.assertEqual(receipt_line("Coffee", 3.5), "Coffee: EUR 3.50")

    def test_account(self):
        account = {"owner": "Ann", "balance": 1500, "currency": "USD"}
        self.assertEqual(balance_label(account), "Ann balance: USD 1,500.00")


if __name__ == "__main__":
    unittest.main()
