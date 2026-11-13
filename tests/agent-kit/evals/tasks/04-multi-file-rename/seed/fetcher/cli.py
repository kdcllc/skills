"""Command line entry point: python3 -m fetcher CONFIG URL"""
import sys

from .client import fetch
from .config import load_config


def main(argv=None):
    args = sys.argv[1:] if argv is None else list(argv)
    if len(args) != 2:
        print("usage: python3 -m fetcher CONFIG URL", file=sys.stderr)
        return 2
    cfg = load_config(args[0])
    print(fetch(cfg, args[1]))
    return 0
