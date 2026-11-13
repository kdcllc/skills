import unittest

from report import inventory_report, payroll_report, sales_report


class ReportTests(unittest.TestCase):
    def test_sales_report(self):
        text = sales_report([("pen", 3, 1.5)])
        self.assertEqual(text.splitlines()[2], "pen             3      4.50")
        self.assertTrue(text.splitlines()[-1].startswith("TOTAL"))

    def test_inventory_report_empty(self):
        self.assertEqual(
            inventory_report([]).splitlines()[-1], "STOCK VALUE            0.00"
        )

    def test_payroll_report(self):
        text = payroll_report([("ann", 8, 20.0)])
        self.assertIn("160.00", text)


if __name__ == "__main__":
    unittest.main()
