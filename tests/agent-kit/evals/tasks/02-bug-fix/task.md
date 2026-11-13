- id: 02-bug-fix
- category: 02-bug-fix
- size: small

## Prompt
Our `paging` helpers give the wrong last page when the number of items divides evenly by the page size. For example, with 20 items and a page size of 10, `page_count(20, 10)` returns 3 instead of 2, and asking for page 3 does not raise an error. Please find the cause and fix it so the helpers behave as their docstrings describe.

## Decisions
- Scope: fix the page arithmetic in the `paging` package only.
- The docstrings in `paging/paginate.py` are the specification for the helpers.
