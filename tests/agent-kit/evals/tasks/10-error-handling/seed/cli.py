"""Summarize a JSON config file.

Usage: python3 cli.py CONFIG.json

The config is a JSON object with a "name" string and a "values" list of
numbers.
"""

import json
import sys


def load_config(path):
    with open(path) as handle:
        return json.load(handle)


def summarize(config):
    name = config["name"]
    values = config["values"]
    return "%s: %d values, total %s" % (name, len(values), sum(values))


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    config = load_config(argv[0])
    print(summarize(config))
    return 0


if __name__ == "__main__":
    sys.exit(main())
