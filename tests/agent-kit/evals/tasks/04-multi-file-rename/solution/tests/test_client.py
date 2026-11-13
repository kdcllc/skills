import unittest

from fetcher.client import fetch


class ClientTest(unittest.TestCase):
    def test_fetch_formats_request(self):
        cfg = {"timeout_s": 5, "retries": 1}
        self.assertEqual(fetch(cfg, "http://x/"), "GET http://x/ (timeout 5s, retries 1)")
