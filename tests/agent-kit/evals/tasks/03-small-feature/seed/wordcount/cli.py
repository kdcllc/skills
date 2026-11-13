"""Command line entry point: python3 -m wordcount [FILE]"""
import argparse
import sys

from .counts import count


def main(argv=None):
    parser = argparse.ArgumentParser(prog="wordcount")
    parser.add_argument("file", nargs="?", help="file to read; standard input if omitted")
    args = parser.parse_args(argv)
    if args.file:
        with open(args.file, encoding="utf-8") as handle:
            text = handle.read()
    else:
        text = sys.stdin.read()
    lines, words, chars = count(text)
    print("%d lines, %d words, %d chars" % (lines, words, chars))
    return 0
