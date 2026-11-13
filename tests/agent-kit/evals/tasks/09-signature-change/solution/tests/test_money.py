import unittest

from money import format_amount


class FormatAmountTests(unittest.TestCase):
    def test_thousands_and_decimals(self):
        self.assertEqual(format_amount(1234.5, "USD"), "USD 1,234.50")

    def test_zero(self):
        self.assertEqual(format_amount(0, "GBP"), "GBP 0.00")


if __name__ == "__main__":
    unittest.main()
