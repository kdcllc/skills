import unittest

from durations.parse import parse_duration


class ParseTest(unittest.TestCase):
    def test_seconds(self):
        self.assertEqual(parse_duration("90s"), 90)

    def test_minutes_and_hours(self):
        self.assertEqual(parse_duration("2m"), 120)
        self.assertEqual(parse_duration("1h"), 3600)

    def test_garbage_rejected(self):
        with self.assertRaises(ValueError):
            parse_duration("abc")
