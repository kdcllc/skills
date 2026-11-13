# wordcount

Counts the lines, words and characters of a file, or of standard input when no
file is given.

    python3 -m wordcount notes.txt
    printf 'a b\nc\n' | python3 -m wordcount

Output is one line, for example `2 lines, 3 words, 6 chars`.

With `--json` the counts are printed as one line of compact JSON instead, for
example `{"lines":2,"words":3,"chars":6}`.

Counting rules: lines is the number of newline characters, words is the number
of whitespace-separated words, chars is the number of characters.
