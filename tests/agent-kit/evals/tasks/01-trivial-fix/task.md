- id: 01-trivial-fix
- category: 01-trivial-fix
- size: trivial

## Prompt
The `unitconv` command prints the wrong unit in its message. Running `python3 -m unitconv 10` prints `10.00 km = 6.21 kilometres`, but 6.21 is a number of miles. Please fix the unit label so the message says miles.

## Decisions
- Scope: only the unit label in the printed message changes.
- Keep the rest of the message format as it is.
