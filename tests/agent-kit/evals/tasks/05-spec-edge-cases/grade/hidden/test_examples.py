import unittest

from durations.parse import parse_duration

EXAMPLES = [
    ("90s", 90), ("2m", 120), ("1h", 3600), ("1h30m", 5400),
    ("1h30m15s", 5415), ("30m1h", 5400), ("0s", 0), ("007s", 7),
    ("  1h 30m  ", 5400), ("1h\t30m", 5400), ("168h", 604800),
    ("10079m60s", 604800), ("100h", 360000),
    # beyond the table, from the rules
    ("0h0m0s", 0), ("1s 1m 1h", 3661), ("\t5s\t", 5), (" 1h \t 30m ", 5400),
    ("604800s", 604800), ("00168h", 604800),
]


class HiddenExamples(unittest.TestCase):
    def test_every_example(self):
        for text, want in EXAMPLES:
            with self.subTest(text=text):
                result = parse_duration(text)
                self.assertEqual(result, want)
                self.assertIs(type(result), int)
