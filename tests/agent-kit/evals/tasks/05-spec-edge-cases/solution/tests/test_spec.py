import unittest

from durations.parse import parse_duration


class SpecTest(unittest.TestCase):
    def test_examples(self):
        for text, want in [("1h30m", 5400), ("30m1h", 5400), ("0s", 0), (" 1h 30m ", 5400), ("168h", 604800)]:
            with self.subTest(text=text):
                self.assertEqual(parse_duration(text), want)

    def test_rejections(self):
        for text in ["", "  ", "-5s", "5d", "1h2h", "90", "1 h", "604801s", "1h\n"]:
            with self.subTest(text=text):
                with self.assertRaises(ValueError):
                    parse_duration(text)

    def test_non_string(self):
        with self.assertRaises(TypeError):
            parse_duration(90)
