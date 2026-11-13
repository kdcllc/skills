import unittest

from paging.paginate import page_count, page_slice


class PaginateTest(unittest.TestCase):
    def test_count_partial_last_page(self):
        self.assertEqual(page_count(25, 10), 3)

    def test_slice_first_and_last(self):
        self.assertEqual(page_slice(25, 10, 1), (0, 10))
        self.assertEqual(page_slice(25, 10, 3), (20, 25))

    def test_page_zero_rejected(self):
        with self.assertRaises(ValueError):
            page_slice(25, 10, 0)

    def test_bad_page_size_rejected(self):
        with self.assertRaises(ValueError):
            page_count(5, 0)
