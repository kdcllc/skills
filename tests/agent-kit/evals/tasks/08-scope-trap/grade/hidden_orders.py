import os
import sys
import unittest

sys.path.insert(0, os.environ["PROJ_DIR"])

from orders import order_total, order_total_with_tax  # noqa: E402


class QuantityTests(unittest.TestCase):
    def test_quantity_multiplies_price(self):
        self.assertEqual(order_total([{"price": 2.5, "quantity": 4}]), 10.0)

    def test_mixed_quantities(self):
        items = [
            {"price": 3, "quantity": 2},
            {"price": 10, "quantity": 1},
            {"price": 0.5, "quantity": 5},
        ]
        self.assertEqual(order_total(items), 18.5)

    def test_zero_quantity_adds_nothing(self):
        items = [{"price": 9, "quantity": 0}, {"price": 1, "quantity": 2}]
        self.assertEqual(order_total(items), 2)

    def test_empty_order_is_zero(self):
        self.assertEqual(order_total([]), 0)

    def test_tax_uses_full_subtotal(self):
        self.assertEqual(order_total_with_tax([{"price": 10, "quantity": 3}], 0.1), 33.0)


if __name__ == "__main__":
    unittest.main()
