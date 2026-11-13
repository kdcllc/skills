import unittest

from paging.paginate import page_slice


class HiddenSlices(unittest.TestCase):
    def test_exact_multiple_last_page(self):
        self.assertEqual(page_slice(20, 10, 2), (10, 20))
        self.assertEqual(page_slice(10, 10, 1), (0, 10))

    def test_single_item_and_one_over(self):
        self.assertEqual(page_slice(1, 10, 1), (0, 1))
        self.assertEqual(page_slice(11, 10, 2), (10, 11))

    def test_partial_last_page(self):
        self.assertEqual(page_slice(25, 10, 3), (20, 25))
