"""Counting rules for wordcount."""


def count(text):
    """Return (lines, words, chars) for `text`.

    lines is the number of newline characters, words the number of
    whitespace-separated words and chars the number of characters.
    """
    return text.count("\n"), len(text.split()), len(text)
