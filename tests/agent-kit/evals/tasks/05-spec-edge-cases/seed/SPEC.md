# parse_duration specification

`parse_duration(text) -> int` turns a duration string into a whole number of
seconds.

## Grammar

A duration is one or more components. A component is a non-empty run of ASCII
digits (`0`-`9`) immediately followed by one unit letter:

| Unit | Meaning | Seconds |
|------|---------|---------|
| `h`  | hours   | 3600    |
| `m`  | minutes | 60      |
| `s`  | seconds | 1       |

Unit letters are lowercase only. The result is the sum of all components.

## Rules

1. Components may appear in any order. `30m1h` is 5400.
2. Each unit may appear at most once. `1h2h` is rejected.
3. Leading zeros are allowed. `007s` is 7. A value of zero is allowed: `0s` is 0.
4. Whitespace means a space or a tab. It is ignored before the first component
   and after the last one, and it is allowed between components. It is not
   allowed between a number and its unit, or inside a number. Any other
   character, including a newline, makes the input invalid.
5. Empty input, and input of only whitespace, is rejected.
6. A number without a unit (`90`), a unit without a number (`h`), a sign
   (`-5s`, `+5s`), a decimal point (`1.5h`) and a non-ASCII digit are rejected.
7. An unknown unit (`5d`, `5x`, `5H`) is rejected.
8. The total may not exceed one week, 604800 seconds. Exactly 604800 is
   allowed (`168h`); 604801 is rejected.
9. Every rejection raises `ValueError`. A value that is not a `str` raises
   `TypeError`.

## Examples

| Input | Result |
|-------|--------|
| `90s` | 90 |
| `2m` | 120 |
| `1h` | 3600 |
| `1h30m` | 5400 |
| `1h30m15s` | 5415 |
| `30m1h` | 5400 |
| `0s` | 0 |
| `007s` | 7 |
| `  1h 30m  ` | 5400 |
| `1h\t30m` | 5400 |
| `168h` | 604800 |
| `10079m60s` | 604800 |
| `100h` | 360000 |
