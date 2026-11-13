import unittest

from orders import order_total, order_total_with_tax


class OrderTests(unittest.TestCase):
    def test_single_units(self):
        items = [{"price": 2.0, "quantity": 1}, {"price": 3.5, "quantity": 1}]
        self.assertEqual(order_total(items), 5.5)

    def test_empty_order(self):
        self.assertEqual(order_total([]), 0)

    def test_with_tax(self):
        self.assertEqual(order_total_with_tax([{"price": 10, "quantity": 1}], 0.1), 11.0)

    def test_quantity_is_counted(self):
        self.assertEqual(order_total([{"price": 2.5, "quantity": 4}]), 10.0)


if __name__ == "__main__":
    unittest.main()
