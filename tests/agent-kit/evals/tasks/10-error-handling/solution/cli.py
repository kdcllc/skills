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


def fail(code, message):
    print("error: " + message, file=sys.stderr)
    return code


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    try:
        config = load_config(argv[0])
    except FileNotFoundError:
        return fail(2, "config file not found: " + argv[0])
    except json.JSONDecodeError as exc:
        return fail(3, "invalid JSON in %s: %s" % (argv[0], exc.msg))
    try:
        text = summarize(config)
    except KeyError as exc:
        return fail(4, "missing required key: " + str(exc.args[0]))
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
