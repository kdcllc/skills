- id: 06-write-tests
- category: 06-write-tests
- size: small

## Prompt
The helpers in textstats.py (word_count, longest_word and truncate) have no tests. Add a unittest suite for them in the tests/ folder that would catch it if someone changed their behaviour later. The docstrings describe the intended behaviour, including the edge cases. Don't change textstats.py itself.

## Decisions
- Put the new tests in a single new file under tests/, using unittest only.
- Do not modify textstats.py.
- Run the new tests against the current code and make sure they pass.
