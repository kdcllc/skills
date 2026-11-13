- id: 04-multi-file-rename
- category: 04-multi-file-rename
- size: medium

## Prompt
Rename the `fetcher` config key `timeout` to `timeout_s`, so the unit is clear. Update everything that uses it: the code, the README examples, the example config and the tests. The old key must keep working for now: when a config file uses `timeout`, loading it still works and emits a `DeprecationWarning`, and the value ends up under `timeout_s`. If both keys are present, `timeout_s` wins. A config that uses only the new key must load without any warning. The old key name must only be read by that deprecation path; nowhere else in the code may refer to `timeout`.

## Decisions
- Scope: the key rename and the deprecation path only; other config keys and defaults stay as they are.
- The loaded config keeps its current shape (a dict), with `timeout_s` in place of `timeout`.
