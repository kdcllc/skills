"""A pretend HTTP client that only formats the request it would send."""


def fetch(cfg, url):
    return "GET %s (timeout %ds, retries %d)" % (url, cfg["timeout"], cfg["retries"])
