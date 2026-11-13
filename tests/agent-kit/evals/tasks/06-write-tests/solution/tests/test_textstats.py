import unittest

from textstats import longest_word, truncate, word_count


class WordCountTests(unittest.TestCase):
    def test_empty_and_blank(self):
        self.assertEqual(word_count(""), 0)
        self.assertEqual(word_count("   \t\n "), 0)

    def test_single_word(self):
        self.assertEqual(word_count("hello"), 1)

    def test_mixed_whitespace(self):
        self.assertEqual(word_count("a  b\tc\nd"), 4)

    def test_repeated_words_all_counted(self):
        self.assertEqual(word_count("go go go"), 3)


class LongestWordTests(unittest.TestCase):
    def test_empty_gives_empty_string(self):
        self.assertEqual(longest_word(""), "")
        self.assertEqual(longest_word("   "), "")

    def test_picks_longest(self):
        self.assertEqual(longest_word("a bbb cc"), "bbb")

    def test_first_wins_on_tie(self):
        self.assertEqual(longest_word("aa bb c"), "aa")
        self.assertEqual(longest_word("c aa bb"), "aa")

    def test_single_word(self):
        self.assertEqual(longest_word("word"), "word")


class TruncateTests(unittest.TestCase):
    def test_short_text_unchanged(self):
        self.assertEqual(truncate("hi", 10), "hi")

    def test_exact_length_unchanged(self):
        self.assertEqual(truncate("abcde", 5), "abcde")

    def test_cut_ends_with_ellipsis_and_has_limit_length(self):
        result = truncate("abcdefghij", 6)
        self.assertEqual(result, "abc...")
        self.assertEqual(len(result), 6)

    def test_one_over_limit_is_cut(self):
        self.assertEqual(truncate("abcdef", 5), "ab...")

    def test_minimum_limit(self):
        self.assertEqual(truncate("abcd", 3), "...")
        self.assertEqual(truncate("abc", 3), "abc")

    def test_limit_below_three_raises(self):
        with self.assertRaises(ValueError):
            truncate("abcdef", 2)
        with self.assertRaises(ValueError):
            truncate("ab", 2)


if __name__ == "__main__":
    unittest.main()
