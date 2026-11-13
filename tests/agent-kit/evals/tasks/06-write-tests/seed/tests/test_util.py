import unittest

from util import clamp


class ClampTests(unittest.TestCase):
    def test_inside_range(self):
        self.assertEqual(clamp(5, 0, 10), 5)

    def test_outside_range(self):
        self.assertEqual(clamp(-3, 0, 10), 0)
        self.assertEqual(clamp(30, 0, 10), 10)


if __name__ == "__main__":
    unittest.main()
