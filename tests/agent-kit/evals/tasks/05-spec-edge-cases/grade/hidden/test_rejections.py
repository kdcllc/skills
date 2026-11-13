import unittest

from durations.parse import parse_duration

REJECTED = {
    "empty": ["", " ", "  \t "],
    "negative and signs": ["-5s", "+5s", "-0s", "1h-5m"],
    "unknown unit": ["5d", "5x", "5H", "5M", "5S", "1h5d", "5w"],
    "repeated unit": ["1h2h", "1m2m", "1s1s", "1h30m1h", "0s0s"],
    "no unit or no number": ["90", "h", "1h30", "m", "1h m"],
    "decimal": ["1.5h", ".5h", "1.h"],
    "whitespace inside": ["1 h", "1h 3 0m", "1\nh", "1h\n", "\n1h", "1h\r", "1h\u00a0", "1h\x0b30m"],
    "non-ascii digit": ["١h", "1٢m", "１h"],
    "other characters": ["1h,30m", "1h+30m", "1h30m!", "abc", "1_0s"],
    "overflow": ["604801s", "10080m1s", "169h", "99999999999999999999s", "168h1s"],
}


class HiddenRejections(unittest.TestCase):
    def test_every_rejection_rule(self):
        for rule, texts in REJECTED.items():
            for text in texts:
                with self.subTest(rule=rule, text=text):
                    with self.assertRaises(ValueError):
                        parse_duration(text)

    def test_non_str_is_type_error(self):
        for value in (90, None, b"90s", 1.5, ["1h"]):
            with self.subTest(value=value):
                with self.assertRaises(TypeError):
                    parse_duration(value)
