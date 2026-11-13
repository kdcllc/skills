- id: 05-spec-edge-cases
- category: 05-spec-edge-cases
- size: medium

## Prompt
`durations.parse.parse_duration` only understands a single component such as `90s` today. Implement it fully as `SPEC.md` describes, including every rule about accepted and rejected input, and add tests for it.

## Decisions
- Scope: `parse_duration` in `durations/parse.py` only; `SPEC.md` is the specification.
- Keep the function name and signature as they are.
