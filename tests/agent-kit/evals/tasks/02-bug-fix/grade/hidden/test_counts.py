import unittest

from paging.paginate import page_count


class HiddenCounts(unittest.TestCase):
    def test_totals(self):
        cases = [
            (0, 10, 0), (1, 10, 1), (9, 10, 1), (10, 10, 1), (11, 10, 2),
            (20, 10, 2), (21, 10, 3), (100, 10, 10), (7, 1, 7), (1, 1, 1),
            (0, 1, 0), (5, 5, 1), (6, 5, 2),
        ]
        for total, size, want in cases:
            with self.subTest(total=total, size=size):
                self.assertEqual(page_count(total, size), want)
