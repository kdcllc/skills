#!/usr/bin/env bash
# trace-lint — consumer-trace linter for the AI Orchestration Kit.
# Emitted single-copy to `_kit/trace-lint.sh` (Windows outside Git Bash:
# `_kit\trace-lint.cmd` — Git for Windows required). Pre-flight check 2 runs it on a
# goal's `goal.md`; it reads that one file and writes nothing.
#
# CLI CONTRACT (frozen — the goal template and goal-criteria describe this):
#
#   trace-lint.sh <goal.md>     lint the goal's `## Searches` and `## Consumers`
#   trace-lint.sh --help        print usage, exit 0
#
#   Exit codes: 0 valid · 2 usage (wrong argument count, unknown flag) · 3 findings ·
#   4 the file is missing or unreadable.
#   stdout, exit 0:  `trace-lint: ok (<S> searches, <C> consumers)`
#                    or `trace-lint: ok (none — <reason>)`
#   stdout, exit 3:  one `trace-lint: <file>:<line>: <message>` line per finding, then a
#                    last line `trace-lint: <N> finding(s)`
#   stderr, exit 2 / 4: one `trace-lint: <message>` line (exit 2 adds the usage text).
#
# FORMAT (the goal template's `## Searches` / `## Consumers` guidance is the source):
#   Parsing: a section runs from a `## <name>` heading to the next `## ` heading. Lines
#   inside fenced blocks are never read as headings.
#   1. Sections: `## Consumers` must exist. When its first non-blank body line starts
#      with `none — ` the trace is valid and `## Searches` must be absent. Otherwise
#      `## Searches` must exist with at least one item, and `## Consumers` must hold the
#      exact header row `| Surface | Consumer | Class | Evidence |` as its first table row.
#   2. Search items: every line in `## Searches` that starts with `- **S` matches the
#      pattern below; `1 hit` is required when N is 1 and `hits` otherwise; the next
#      non-blank line opens a text fence; the fence holds N non-empty lines.
#        PCRE notation, for readers:
#          ^\s*- \*\*S([0-9]+)\*\* (`+)(.*)\2 — ([0-9]+) (hit|hits)$
#        This tool implements it in POSIX terms: [[:space:]] for \s, the backtick-span
#        back-reference in BRE (sed), and the hit|hits alternation as a separate check.
#   3. Unique ids: no `S<n>` repeats.
#   4. Hit lines (after trimming leading whitespace and a leading `./`) match
#      `^[^:]*[^0-9:][^:]*:[0-9]+:` — a path that is not all digits, then a line number.
#   5. Every hit path not under `_memory/` is a Consumer: the Consumer column, after
#      splitting the row on unescaped `|` (`\|` is a literal pipe) and stripping
#      backticks and spaces.
#   6. Class is exactly `changes`, `unaffected` or `owner-excluded`.
#   7. `unaffected` evidence starts with `test: `, `diff: ` or `search: S<n>`; a
#      `search:` reference names an existing search with 0 hits.
#   8. `owner-excluded` evidence contains `Q&A row <n>`, and `## Discovery Summary`'s
#      table has a row whose first cell is `<n>`.
#   9. `changes` evidence contains `task <NN>` (two digits, optional letter) or is
#      exactly `Phase 6`; `Phase 6` is valid only when the goal has a line matching
#      `^[[:space:]]*align_docs:[[:space:]]*true[[:space:]]*(#.*)?$` (the template's
#      `align_docs: true|false` placeholder does not match).
#   Findings print in the order the checks run: the single pass over the file first,
#   then the Consumer rows in row order, then unlisted hits in file order.
#
# Zero runtime deps beyond bash + sed. Bash 3.2 compatible: no associative arrays, no
# case-folding expansions, no JSON tools. No setup placeholders — harness-agnostic.
set -u
LC_ALL=C
export LC_ALL

NL='
'
BT='`'

usage() {
  printf '%s\n' \
    'usage: trace-lint.sh <goal.md>' \
    '       trace-lint.sh --help' \
    "Checks the goal's '## Searches' and '## Consumers' sections (the consumer trace)." \
    'exit: 0 valid · 2 usage · 3 findings · 4 file missing or unreadable'
}

die() { # <code> <message>
  printf 'trace-lint: %s\n' "$2" >&2
  exit "$1"
}

for a in "$@"; do
  [ "$a" = "--help" ] && { usage; exit 0; }
done
for a in "$@"; do
  case "$a" in
    -?*) usage >&2; die 2 "unknown flag '$a'" ;;
  esac
done
[ $# -eq 1 ] || { usage >&2; die 2 "expected exactly one argument: the goal.md path"; }
file="$1"
if [ ! -f "$file" ] || [ ! -r "$file" ]; then
  die 4 "file not found or unreadable: $file"
fi

# --- patterns -----------------------------------------------------------------------
ALIGN_RE='^[[:space:]]*align_docs:[[:space:]]*true[[:space:]]*(#.*)?$'
HIT_RE='^[^:]*[^0-9:][^:]*:[0-9]+:'
SEP_RE='^[|][-:| ]*-[-:| ]*$'
TASK_RE='task [0-9][0-9]([^0-9]|$)'
HEADER_ROW='| Surface | Consumer | Class | Evidence |'
# Rule 2 in BRE: \1 = S number, \2 = the backtick run, \3 = the command, \4 = N, \5 = the
# count word (hit|hits is checked separately). Prints "<S number> <N> <word>" on a match.
ITEM_SED='s/^[[:space:]]*- \*\*S\([0-9][0-9]*\)\*\* \(`\{1,\}\)\(.*\)\2 — \([0-9][0-9]*\) \([A-Za-z]*\)$/\1 \4 \5/p'

MSG_ITEM='malformed search item (want: - **S<n>** `<command>` — <N> hit, or hits)'
MSG_UNAFF="unaffected evidence must start with 'test: ', 'diff: ' or 'search: S<n>'"

# --- helpers --------------------------------------------------------------------------
nf=0
finding() { # <line> <message>
  printf 'trace-lint: %s:%s: %s\n' "$file" "$1" "$2"
  nf=$((nf + 1))
}

trim() { # <text> → T (leading and trailing whitespace removed)
  T="${1#"${1%%[![:space:]]*}"}"
  T="${T%"${T##*[![:space:]]}"}"
}

split_row() { # <table row> → CELLS (trimmed; `\|` becomes `|`), NCELLS
  local s="$1" i=0 n ch cur=""
  CELLS=()
  NCELLS=0
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s#|}"
  n=${#s}
  while [ "$i" -lt "$n" ]; do
    ch="${s:$i:1}"
    if [ "$ch" = '\' ] && [ "${s:$((i + 1)):1}" = '|' ]; then
      cur="$cur|"
      i=$((i + 2))
      continue
    fi
    if [ "$ch" = '|' ]; then
      trim "$cur"
      CELLS[$NCELLS]="$T"
      NCELLS=$((NCELLS + 1))
      cur=""
    else
      cur="$cur$ch"
    fi
    i=$((i + 1))
  done
  trim "$cur"
  if [ -n "$T" ]; then
    CELLS[$NCELLS]="$T"
    NCELLS=$((NCELLS + 1))
  fi
}

parse_item() { # reads $line / $lineno; registers the search and arms the fence check
  local m sid sn sw n
  items=$((items + 1))
  m="$(printf '%s\n' "$line" | sed -n "$ITEM_SED")"
  if [ -z "$m" ]; then
    finding "$lineno" "$MSG_ITEM"
    return
  fi
  read -r sid sn sw <<< "$m"
  n=$((10#$sn))
  case "$sw" in
    hit)  [ "$n" -eq 1 ] || finding "$lineno" "S$sid: the word 'hit' is only for a count of 1 (write '$n hits')" ;;
    hits) [ "$n" -ne 1 ] || finding "$lineno" "S$sid: '1 hits' is invalid (write '1 hit')" ;;
    *)    finding "$lineno" "$MSG_ITEM"; return ;;
  esac
  case "$NL$sids" in
    *"$NL$sid$NL"*) finding "$lineno" "duplicate search id S$sid" ;;
  esac
  sids="$sids$sid$NL"
  counts="$counts$sid:$n$NL"
  pending=1
  pend_id="$sid"
  pend_n="$n"
  pend_line="$lineno"
}

# --- single pass: sections, searches, hits, raw table rows ----------------------------
lineno=0
fence=0               # backtick count of the open fence; 0 = not inside one
sec=""                # consumers | searches | discovery | other ("" before the first ##)
cons_line=0           # heading line of ## Consumers (0 = absent)
search_line=0         # heading line of ## Searches (0 = absent)
cons_first=""         # first non-blank body line of ## Consumers
cons_first_line=0
cons_rows=""          # "<lineno> <row>" per table row of ## Consumers
disc_rows=""          # first cells (digits) of ## Discovery Summary table rows
sids=""               # search ids, one per line
counts=""             # "<id>:<N>" per search, one per line
hits=""               # "<lineno> <path>" per well-formed hit line
items=0               # search items seen
align_docs=0
pending=0             # 1 while the last search item still awaits its text fence
pend_id="" pend_n=0 pend_line=0
in_hit=0              # 1 inside the text fence that belongs to a search item
cur_id="" cur_n=0 cur_line=0 hit_n=0 hit_open=0

while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  lineno=$((lineno + 1))
  if [[ "$line" =~ $ALIGN_RE ]]; then align_docs=1; fi
  trim "$line"
  t="$T"

  if [ "$sec" = consumers ] && [ -n "$t" ] && [ "$cons_first_line" -eq 0 ]; then
    cons_first="$t"
    cons_first_line=$lineno
  fi

  # fenced blocks: openers, closers and content never reach the heading/section logic
  if [ "${t:0:3}" = '```' ]; then
    after="$t"
    ticks=0
    while [ "${after:0:1}" = "$BT" ]; do
      ticks=$((ticks + 1))
      after="${after:1}"
    done
    trim "$after"
    info="$T"
    if [ "$fence" -eq 0 ]; then
      case "$info" in
        *"$BT"*) ;;                                   # an inline span such as ```x```
        *)
          fence=$ticks
          if [ "$sec" = searches ] && [ "$pending" -eq 1 ]; then
            pending=0
            if [ "$info" = text ]; then
              in_hit=1
              hit_n=0
              hit_open=$lineno
              cur_id="$pend_id"
              cur_n="$pend_n"
              cur_line="$pend_line"
            else
              finding "$pend_line" "S$pend_id: the next non-blank line must open a "'```text'" block"
            fi
          fi
          continue ;;
      esac
    elif [ "$ticks" -ge "$fence" ] && [ -z "$info" ]; then
      if [ "$in_hit" -eq 1 ] && [ "$hit_n" -ne "$cur_n" ]; then
        finding "$cur_line" "S$cur_id declares $cur_n hit(s) but its block has $hit_n non-empty line(s)"
      fi
      fence=0
      in_hit=0
      continue
    fi
  fi
  if [ "$fence" -gt 0 ]; then
    if [ "$in_hit" -eq 1 ] && [ -n "$t" ]; then
      hit_n=$((hit_n + 1))
      h="${t#./}"
      if [[ "$h" =~ $HIT_RE ]]; then
        hits="$hits$lineno ${h%%:*}$NL"
      else
        finding "$lineno" "hit has no path (use -H): ${h:0:60}"
      fi
    fi
    continue
  fi

  # headings
  case "$line" in
    '## '*)
      if [ "$sec" = searches ] && [ "$pending" -eq 1 ]; then
        pending=0
        finding "$pend_line" "S$pend_id: the next non-blank line must open a "'```text'" block"
      fi
      trim "${line:3}"
      case "$T" in
        Consumers)
          sec=consumers
          [ "$cons_line" -eq 0 ] && cons_line=$lineno ;;
        Searches)
          sec=searches
          [ "$search_line" -eq 0 ] && search_line=$lineno ;;
        'Discovery Summary'*) sec=discovery ;;
        *) sec=other ;;
      esac
      continue ;;
  esac

  [ -n "$t" ] || continue
  case "$sec" in
    searches)
      if [ "$pending" -eq 1 ]; then
        pending=0
        finding "$pend_line" "S$pend_id: the next non-blank line must open a "'```text'" block"
      fi
      case "$t" in
        '- **S'*) parse_item ;;
      esac ;;
    consumers)
      case "$t" in
        '|'*) cons_rows="$cons_rows$lineno $t$NL" ;;
      esac ;;
    discovery)
      case "$t" in
        '|'*)
          cell="${t#|}"
          cell="${cell%%|*}"
          trim "$cell"
          case "$T" in
            ''|*[!0-9]*) ;;
            *) disc_rows="$disc_rows$T$NL" ;;
          esac ;;
      esac ;;
  esac
done < "$file"

if [ "$pending" -eq 1 ]; then
  finding "$pend_line" "S$pend_id: the next non-blank line must open a "'```text'" block"
fi
if [ "$in_hit" -eq 1 ]; then
  finding "$hit_open" "unterminated "'```text'" block for S$cur_id"
fi

# --- rule 1 and the consumer-dependent rules -------------------------------------------
none=0
none_reason=""
consumers=0
if [ "$cons_line" -eq 0 ]; then
  finding 1 "missing '## Consumers' section"
else
  case "$cons_first" in
    'none — '*)
      none=1
      none_reason="${cons_first#none — }" ;;
  esac
  if [ "$none" -eq 1 ]; then
    if [ "$search_line" -ne 0 ]; then
      finding "$search_line" "'## Searches' must be absent when '## Consumers' is 'none — <reason>'"
    fi
  else
    if [ "$search_line" -eq 0 ]; then
      finding "$cons_line" "missing '## Searches' section (a goal that changes no shared surface writes 'none — <reason>' under '## Consumers')"
    elif [ "$items" -eq 0 ]; then
      finding "$search_line" "'## Searches' has no items"
    fi

    first_row=1
    cons_paths=""
    while IFS= read -r row || [ -n "$row" ]; do
      [ -n "$row" ] || continue
      rl="${row%% *}"
      rt="${row#* }"
      if [ "$first_row" -eq 1 ]; then          # the first table row is the header row
        first_row=0
        if [ "$rt" != "$HEADER_ROW" ]; then
          finding "$rl" "'## Consumers' must hold the header row '$HEADER_ROW'"
        fi
        continue
      fi
      if [[ "$rt" =~ $SEP_RE ]]; then continue; fi
      consumers=$((consumers + 1))
      split_row "$rt"
      cpath="${CELLS[1]:-}"
      cpath="${cpath//"$BT"/}"
      trim "$cpath"
      cons_paths="$cons_paths$T$NL"
      class="${CELLS[2]:-}"
      ev="${CELLS[3]:-}"
      case "$class" in
        changes)
          if [ "$ev" = 'Phase 6' ]; then
            if [ "$align_docs" -ne 1 ]; then
              finding "$rl" "changes evidence 'Phase 6' is valid only when the goal sets 'align_docs: true' in its phases block"
            fi
          elif [[ "$ev" =~ $TASK_RE ]]; then
            :
          else
            finding "$rl" "changes evidence must contain 'task <NN>' or be exactly 'Phase 6' (got '$ev')"
          fi ;;
        unaffected)
          case "$ev" in
            'test: '*|'diff: '*) ;;
            'search: S'*)
              rest="${ev#search: S}"
              sid="${rest%%[!0-9]*}"
              if [ -z "$sid" ]; then
                finding "$rl" "$MSG_UNAFF"
              else
                case "$NL$counts" in
                  *"$NL$sid:0$NL"*) ;;
                  *"$NL$sid:"*) finding "$rl" "unaffected evidence 'search: S$sid' names a search with hits (needs 0 hits)" ;;
                  *) finding "$rl" "unaffected evidence 'search: S$sid' names no search in '## Searches'" ;;
                esac
              fi ;;
            *) finding "$rl" "$MSG_UNAFF" ;;
          esac ;;
        owner-excluded)
          case "$ev" in
            *'Q&A row '*)
              rest="${ev#*Q&A row }"
              qn="${rest%%[!0-9]*}"
              if [ -z "$qn" ]; then
                finding "$rl" "owner-excluded evidence must contain 'Q&A row <n>' (n = a number)"
              else
                case "$NL$disc_rows" in
                  *"$NL$qn$NL"*) ;;
                  *) finding "$rl" "'Q&A row $qn' is not a row of '## Discovery Summary'" ;;
                esac
              fi ;;
            *) finding "$rl" "owner-excluded evidence must contain 'Q&A row <n>'" ;;
          esac ;;
        *)
          finding "$rl" "class '$class' must be exactly changes, unaffected or owner-excluded" ;;
      esac
    done <<< "$cons_rows"
    if [ "$first_row" -eq 1 ]; then            # no table row at all
      finding "$cons_line" "'## Consumers' must hold the header row '$HEADER_ROW'"
    fi

    unlisted=""
    while IFS= read -r h || [ -n "$h" ]; do
      [ -n "$h" ] || continue
      hl="${h%% *}"
      hp="${h#* }"
      case "$hp" in _memory/*) continue ;; esac
      case "$NL$cons_paths" in *"$NL$hp$NL"*) continue ;; esac
      case "$NL$unlisted" in *"$NL$hp$NL"*) continue ;; esac
      unlisted="$unlisted$hp$NL"
      finding "$hl" "hit path '$hp' is not listed as a Consumer"
    done <<< "$hits"
  fi
fi

if [ "$nf" -gt 0 ]; then
  printf 'trace-lint: %s finding(s)\n' "$nf"
  exit 3
fi
if [ "$none" -eq 1 ]; then
  printf 'trace-lint: ok (none — %s)\n' "$none_reason"
else
  printf 'trace-lint: ok (%s searches, %s consumers)\n' "$items" "$consumers"
fi
exit 0
