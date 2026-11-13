import unittest

from paging.paginate import page_count, page_slice


class HiddenInvalid(unittest.TestCase):
    def test_page_past_last_on_exact_multiple(self):
        with self.assertRaises(ValueError):
            page_slice(20, 10, 3)
        with self.assertRaises(ValueError):
            page_slice(10, 10, 2)

    def test_page_past_last_on_partial(self):
        with self.assertRaises(ValueError):
            page_slice(25, 10, 4)

    def test_zero_items_have_no_valid_page(self):
        with self.assertRaises(ValueError):
            page_slice(0, 10, 1)

    def test_page_below_one(self):
        for page in (0, -1):
            with self.subTest(page=page):
                with self.assertRaises(ValueError):
                    page_slice(20, 10, page)

    def test_bad_sizes(self):
        with self.assertRaises(ValueError):
            page_count(-1, 10)
        with self.assertRaises(ValueError):
            page_slice(10, 0, 1)
