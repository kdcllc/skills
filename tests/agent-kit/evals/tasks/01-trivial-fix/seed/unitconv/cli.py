"""Command line entry point: python3 -m unitconv KM"""
import sys

from .convert import km_to_miles


def main(argv=None):
    args = sys.argv[1:] if argv is None else list(argv)
    if len(args) != 1:
        print("usage: python3 -m unitconv KM", file=sys.stderr)
        return 2
    try:
        km = float(args[0])
    except ValueError:
        print("error: not a number: " + args[0], file=sys.stderr)
        return 2
    print("%.2f km = %.2f kilometres" % (km, km_to_miles(km)))
    return 0
