- id: 10-error-handling
- category: 10-error-handling
- size: small

## Prompt
cli.py reads a JSON config file and prints a summary, but it crashes with a traceback when the file is missing, when it is not valid JSON, or when a required key ("name" or "values") is missing. Make it fail cleanly instead: print one line starting with "error:" followed by a short message to stderr, with no traceback, and exit with code 2 when the file does not exist, 3 when the file is not valid JSON, and 4 when a required key is missing. A valid config must still print exactly what it prints today and exit 0.

## Decisions
- Keep the error handling in cli.py.
- Keep the existing tests passing; adding tests is optional.
