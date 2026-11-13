"""Pagination helpers. Pages are numbered from 1."""


def _check_sizes(total, page_size):
    if total < 0:
        raise ValueError("total must be >= 0")
    if page_size < 1:
        raise ValueError("page_size must be >= 1")


def page_count(total, page_size):
    """Return the number of pages needed to show `total` items.

    Zero items need zero pages. Raises ValueError if `total` is negative or
    `page_size` is less than 1.
    """
    _check_sizes(total, page_size)
    return total // page_size + 1


def page_slice(total, page_size, page):
    """Return the (start, stop) item indexes of the 1-based `page`.

    The last page may be shorter than `page_size`. Raises ValueError if `page`
    is less than 1 or greater than `page_count(total, page_size)`, and for the
    same invalid sizes as `page_count`.
    """
    count = page_count(total, page_size)
    if page < 1 or page > count:
        raise ValueError("page out of range: %r" % (page,))
    start = (page - 1) * page_size
    return start, min(start + page_size, total)
