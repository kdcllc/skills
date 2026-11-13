import unittest

from wordcount.counts import count


class CountTest(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(count("a b\nc\n"), (2, 3, 6))

    def test_empty(self):
        self.assertEqual(count(""), (0, 0, 0))

    def test_no_trailing_newline(self):
        self.assertEqual(count("one two"), (0, 2, 7))
