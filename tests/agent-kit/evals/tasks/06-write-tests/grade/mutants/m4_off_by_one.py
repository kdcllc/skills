"""Small text statistics helpers."""


def word_count(text):
    """Return the number of words in text.

    Words are separated by any run of whitespace. Repeated words are all
    counted.
    """
    return len(text.split())


def longest_word(text):
    """Return the longest whitespace-separated word in text.

    When several words share the longest length the first one wins. Return an
    empty string when text has no words.
    """
    best = ""
    for word in text.split():
        if len(word) > len(best):
            best = word
    return best


def truncate(text, limit):
    """Return text unchanged when it has at most limit characters.

    Otherwise cut it so the result is exactly limit characters long and ends
    with "...". Raise ValueError when limit is less than 3.
    """
    if limit < 3:
        raise ValueError("limit must be at least 3")
    if len(text) <= limit:
        return text
    return text[: limit - 2] + "..."
