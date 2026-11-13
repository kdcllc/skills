- id: 03-small-feature
- category: 03-small-feature
- size: small

## Prompt
Add a `--json` flag to the `wordcount` command. With the flag, it prints the counts as one line of compact JSON with the keys in this order, for example `{"lines":2,"words":5,"chars":24}`: no spaces after the colons or commas. Without the flag the output must stay exactly as it is today. The README documents the command; add a short note about the new flag and add tests for it.

## Decisions
- Scope: `--json` only; the counting rules stay as the README describes them.
- The flag works with a file argument and with standard input.
