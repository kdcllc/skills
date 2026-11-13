import unittest

from unitconv.convert import km_to_miles


class KmToMilesTest(unittest.TestCase):
    def test_zero(self):
        self.assertEqual(km_to_miles(0), 0)

    def test_marathon(self):
        self.assertAlmostEqual(km_to_miles(42.195), 26.2188, places=3)
