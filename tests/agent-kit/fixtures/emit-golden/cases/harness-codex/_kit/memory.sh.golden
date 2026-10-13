#!/usr/bin/env bash
# memory — add, index, search, and show immutable _memory/ records for the AI Orchestration Kit.
# Twin: memory.ps1 (PowerShell 7.2+) — behaviorally identical — any divergence is a bug;
# memory.ps1 is retained as a helper for loop.ps1 until loop twins retire.
# Emitted single-copy to `_kit/memory.sh` (Windows outside Git Bash: `_kit\memory.cmd`).
#
#   memory.sh add --kind <k> --title <t> --body <path>
#             [--source <s>] [--tags <list>] [--supersedes <list>] [--harness <h>] [--root <dir>]
#   memory.sh index [--root <dir>]
#   memory.sh search <term>... [--kind <list>] [--limit <n>] [--include-superseded]
#             [--engine grep|fts] [--root <dir>]
#   memory.sh show <id> [--root <dir>]
#
# Exit codes: 0 ok · 2 usage/format · 4 missing root, file, id, or optional dependency · 5 quarantined.
# Errors: one line on stderr prefixed `memory: `. Store path: `<root>/_memory/`.
#
# Portability: bash 3.2+, LC_ALL=C, coreutils/grep/sed/awk/find; optional sqlite3 (FTS5 auto-detect).
set -euo pipefail
set -f
export LC_ALL=C

TAB="$(printf '\t')"
NL="$(printf '\nx')"
NL="${NL%x}"
# ASCII unit separator: internal delimiter for record-read lists (items may contain spaces).
US="$(printf '\037')"
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/memory.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

mk_tmp() {
  mktemp "$TMPD/t.XXXXXX"
}

# Search terms (cmd_search sets; batch search awk reads).
TERMS=()

re_match() { # <string> <ere>
  case "$1" in
    *"$NL"*) return 1 ;;
  esac
  printf '%s\n' "$1" | LC_ALL=C grep -Eq -- "$2"
}

# LC_ALL=C; equivalent to re_id ERE without forking grep.
valid_record_id() { # <id>
  case "$1" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) return 0 ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<'EOF'
usage: memory.sh <add|index|search|show> [--root <dir>] ...
  add    --kind <k> --title <t> --body <path> [--source <s>] [--tags <list>] [--supersedes <list>] [--harness <h>]
  index  [--root <dir>]
  search <term>... [--kind <list>] [--limit <n>] [--include-superseded] [--engine grep|fts]
  show   <id> [--root <dir>]
exit: 0 ok · 2 usage/format · 4 missing root/file/id/dependency · 5 quarantined
EOF
}

die() { # <code> <message>
  printf 'memory: %s\n' "$2" >&2
  exit "$1"
}

need_val() { # <flag>
  [ $# -ge 2 ] || die 2 "flag '$1' needs a value"
  [ "${2#--}" = "$2" ] || die 2 "flag '$1' needs a value"
}

# --- formats (ERE, LC_ALL=C) ---
re_id='^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$'
re_tag='^[a-z0-9][a-z0-9-]*$'
re_limit='^[1-9][0-9]*$'
re_memory_now='^[0-9]{8}T[0-9]{6}Z$'

valid_kind() {
  case "$1" in
    goal-summary|spawn-digest|session-summary|research-ingest|decision|learning|fact|pitfall) return 0 ;;
    *) return 1 ;;
  esac
}

valid_harness() {
  case "$1" in
    claude|cursor|copilot|codex) return 0 ;;
    *) return 1 ;;
  esac
}

byte_len() { # <string>
  printf '%s' "$1" | wc -c | tr -d '[:space:]'
}

escape_source() { # <string> → stdout
  printf '%s' "$1" | sed 's/"/'"'"'/g;s/\\/\//g'
}

# Trim ASCII space (0x20) only.
trim_ascii_sp() {
  local s="$1"
  while [ "${s# }" != "$s" ]; do s="${s# }"; done
  while [ "${s% }" != "$s" ]; do s="${s% }"; done
  printf '%s' "$s"
}

# parse comma list: sets global PARSED_LIST_ITEMS (space-separated, safe ids/tags/kinds)
parse_list() { # <list-string> <mode: tag|id|kind>
  local raw="$1" mode="$2" part items="" seen="" item
  PARSED_LIST_ITEMS=""
  [ -n "$raw" ] || return 0
  local rest="$raw"
  while [ -n "$rest" ]; do
    part="${rest%%,*}"
    if [ "$part" = "$rest" ]; then
      rest=""
    else
      rest="${rest#*,}"
    fi
    item="$(trim_ascii_sp "$part")"
    [ -n "$item" ] || continue
    case "$mode" in
      tag)
        re_match "$item" "$re_tag" || return 1
        ;;
      id)
        re_match "$item" "$re_id" || return 1
        ;;
      kind)
        valid_kind "$item" || return 1
        ;;
    esac
    case " $seen " in
      *" $item "*) ;;
      *)
        seen="$seen $item"
        items="${items:+$items }$item"
        ;;
    esac
  done
  PARSED_LIST_ITEMS="$items"
  return 0
}

list_to_yaml_inline() { # space-separated items → [a, b] or []
  local items="$1" out="" x
  [ -n "$items" ] || { printf '[]'; return; }
  for x in $items; do
    out="${out:+$out, }$x"
  done
  printf '[%s]' "$out"
}

list_to_comma_nospace() { # US-separated record-list items (REC_LIST_ITEMS) → a,b for manifest
  local rest="$1" out="" x
  while [ -n "$rest" ]; do
    x="${rest%%"$US"*}"
    if [ "$x" = "$rest" ]; then rest=""; else rest="${rest#*"$US"}"; fi
    [ -n "$x" ] || continue
    out="${out:+$out,}$x"
  done
  printf '%s' "$out"
}

default_root() {
  local r
  r="$(git rev-parse --show-toplevel 2>/dev/null)" || r="$PWD"
  printf '%s' "$r"
}

resolve_root() { # <root-arg>
  local r="$1"
  [ -d "$r" ] || die 4 "root directory not found: $r"
  printf '%s' "$r"
}

store_dir() { # <root>
  printf '%s/_memory' "$1"
}

relpath_under_root() { # <root> <abs-path>
  local root="$1" path="$2"
  case "$path" in
    "$root"/*) path="${path#"$root"/}" ;;
  esac
  printf '%s' "${path//\\//}"
}

id_to_record_path() { # <store> <id> → abs path under records/
  local store="$1" id="$2" yyyy mm
  yyyy="${id:0:4}"
  mm="${id:4:2}"
  printf '%s/records/%s/%s/%s.md' "$store" "$yyyy" "$mm" "$id"
}

id_to_quarantine_path() { # <store> <id>
  printf '%s/quarantine/%s.md' "$1" "$2"
}

sha256_hex() { # <file-or-stdin-marker> — reads stdin
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    die 4 "no sha256 tool"
  fi
}

have_sha256() {
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1
}

commit_short() { # <root>
  local c
  c="$(git -C "$1" rev-parse --short=12 HEAD 2>/dev/null)" || c="none"
  printf '%s' "$c"
}

utc_now_id_prefix() {
  date -u +%Y%m%dT%H%M%SZ
}

# NUL check before reading body into variables (evaluator note a).
body_has_nul() { # <path>
  tr -d '\000' < "$1" | cmp -s - "$1"
  local st=$?
  [ "$st" -ne 0 ]
}

normalize_body_file() { # <in-path> <out-path>
  local in="$1" out="$2" endlf=0
  [ -s "$in" ] && [ "$(tail -c 1 "$in" | od -An -tx1 | tr -d ' \n')" = "0a" ] && endlf=1
  awk -v endlf="$endlf" '
    {
      if (NR==1 && length($0)>=3 && substr($0,1,3)==sprintf("%c%c%c",239,187,191)) {
        $0=substr($0,4)
      }
      lines[++n]=$0
    }
    END {
      for (i=1;i<=n;i++) if (i<n || endlf) sub(/\r$/, "", lines[i])
      while (n>0 && lines[n] ~ /^[ \t]*$/) n--
      if (n<1) exit 1
      for (i=1;i<=n;i++) print lines[i]
    }
  ' "$in" > "$out" || return 1
  # Ensure exactly one trailing LF (awk print adds newline per line; no extra blank line at end)
  local bytes
  bytes="$(wc -c < "$out" | tr -d '[:space:]')"
  if [ "$bytes" -eq 0 ]; then
    return 1
  fi
  return 0
}

prepare_body_file() { # <in-path> → writes normalized body to stdout path; die on error
  local in="$1" tmp len
  [ -f "$in" ] && [ -r "$in" ] || die 4 "body file not found: $in"
  body_has_nul "$in" && die 2 "body contains NUL byte"
  tmp="$(mk_tmp)"
  normalize_body_file "$in" "$tmp" || die 2 "invalid body"
  len="$(wc -c < "$tmp" | tr -d '[:space:]')"
  [ "$len" -ge 1 ] || die 2 "invalid body"
  [ "$len" -le 4096 ] || die 2 "invalid body"
  printf '%s' "$tmp"
}

ascii_fold_line() { # <line> → stdout (A-Z → a-z)
  printf '%s' "$1" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'
}

# Frozen ERE alternation; the README literal `<\|?im_start\|?>` is equivalent to the code's `<[|]?im_start[|]?>`.
ADMISSION_ERE='ignore (all )?(previous|prior|above) instructions|disregard (all )?(previous|prior|above)|you must now|new instructions:|<[|]?im_start[|]?>|</?system>'

admission_violation() { # <title> <body-file>
  local title="$1" body_file="$2" folded_body
  ascii_fold_line "$title" | LC_ALL=C grep -Eq "$ADMISSION_ERE" && return 0
  folded_body="$(mk_tmp)"
  tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz' < "$body_file" > "$folded_body"
  LC_ALL=C grep -Eq "$ADMISSION_ERE" "$folded_body" && return 0
  return 1
}

# Read frontmatter keys from record file; sets FM_* globals. Returns 0 ok, 1 malformed.
read_frontmatter() { # <path>
  local path="$1" line key val in_fm=0 closed=0
  local h_id=0 h_kind=0 h_title=0 h_date=0 h_source=0 h_commit=0 h_harness=0 h_tags=0 h_sup=0 h_sha=0
  FM_ID="" FM_KIND="" FM_TITLE="" FM_DATE="" FM_SOURCE="" FM_COMMIT="" FM_HARNESS=""
  FM_TAGS="" FM_SUPERSEDES="" FM_SHA256=""
  if [ ! -f "$path" ]; then return 1; fi
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [ "$in_fm" -eq 0 ]; then
      [ "$line" = "---" ] || return 1
      in_fm=1
      continue
    fi
    if [ "$line" = "---" ]; then
      closed=1
      break
    fi
    key="${line%%:*}"
    val="${line#*: }"
    case "$key" in
      id) FM_ID="$val"; h_id=1 ;;
      kind) FM_KIND="$val"; h_kind=1 ;;
      title)
        val="${val#\"}"; val="${val%\"}"
        FM_TITLE="$val"
        h_title=1
        ;;
      date) FM_DATE="$val"; h_date=1 ;;
      source)
        val="${val#\"}"; val="${val%\"}"
        FM_SOURCE="$val"
        h_source=1
        ;;
      commit) FM_COMMIT="$val"; h_commit=1 ;;
      harness)
        val="${val#\"}"; val="${val%\"}"
        FM_HARNESS="$val"
        h_harness=1
        ;;
      tags)
        FM_TAGS="$val"
        h_tags=1
        ;;
      supersedes) FM_SUPERSEDES="$val"; h_sup=1 ;;
      sha256) FM_SHA256="$val"; h_sha=1 ;;
      quarantined) ;;
    esac
  done < "$path"
  [ "$closed" -eq 1 ] || return 1
  [ "$h_id" -eq 1 ] && [ "$h_kind" -eq 1 ] && [ "$h_title" -eq 1 ] && [ "$h_date" -eq 1 ] &&
    [ "$h_source" -eq 1 ] && [ "$h_commit" -eq 1 ] && [ "$h_harness" -eq 1 ] &&
    [ "$h_tags" -eq 1 ] && [ "$h_sup" -eq 1 ] && [ "$h_sha" -eq 1 ] || return 1
  return 0
}

glob_record_files() { # <store> <out-list-file>
  local store="$1" out="$2" f id
  : > "$out"
  [ -d "$store/records" ] || return 0
  find -L "$store/records" -mindepth 3 -maxdepth 3 -type f -name '*.md' 2>/dev/null | while IFS= read -r f; do
    case "$f" in
      */records/[0-9][0-9][0-9][0-9]/[0-9][0-9]/*.md) ;;
      *) continue ;;
    esac
    id="${f##*/}"; id="${id%.md}"
    valid_record_id "$id" || continue
    printf '%s\n' "$f"
  done >> "$out" || true
}

glob_dedupe_files() { # <store> <out-list-file> — records + quarantine
  local store="$1" out="$2" f id
  : > "$out"
  glob_record_files "$store" "$out"
  if [ -d "$store/quarantine" ]; then
    find -L "$store/quarantine" -maxdepth 1 -type f -name '*.md' 2>/dev/null | while IFS= read -r f; do
      id="${f##*/}"; id="${id%.md}"
      valid_record_id "$id" || continue
      printf '%s\n' "$f"
    done >> "$out" || true
  fi
}

write_record_file() { # <path> ... <sha> <body-file> [quarantine: 0|1]
  local path="$1" id="$2" kind="$3" title="$4" date="$5" source="$6" commit="$7" harness="$8"
  local tags_items="$9" sup_items="${10}" sha="${11}" body_file="${12}" quarantine="${13:-0}"
  local tags_yaml sup_yaml src_esc dir
  tags_yaml="$(list_to_yaml_inline "$tags_items")"
  sup_yaml="$(list_to_yaml_inline "$sup_items")"
  src_esc="$(escape_source "$source")"
  dir="$(dirname "$path")"
  mkdir -p "$dir"
  {
    printf '%s\n' '---'
    printf 'id: %s\n' "$id"
    printf 'kind: %s\n' "$kind"
    printf 'title: "%s"\n' "$title"
    printf 'date: %s\n' "$date"
    printf 'source: "%s"\n' "$src_esc"
    printf 'commit: %s\n' "$commit"
    printf 'harness: "%s"\n' "$harness"
    printf 'tags: %s\n' "$tags_yaml"
    printf 'supersedes: %s\n' "$sup_yaml"
    printf 'sha256: %s\n' "$sha"
    [ "$quarantine" = "1" ] && printf '%s\n' 'quarantined: true'
    printf '%s\n' '---'
    cat "$body_file"
  } > "$path"
}

fts5_available() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  sqlite3 :memory: "CREATE VIRTUAL TABLE t USING fts5(x);" >/dev/null 2>&1
}

sql_escape_sq() { # <string>
  printf '%s' "$1" | sed "s/'/''/g"
}

build_fts_db() { # <store> — MEM_AWK_LISTFILE must be set
  local store="$1" db="$store/.index/fts.db" sql listfile
  listfile="${MEM_AWK_LISTFILE:-}"
  [ -n "$listfile" ] || return 1
  mkdir -p "$store/.index"
  rm -f "$db"
  sql="$(mk_tmp)"
  {
    printf "CREATE VIRTUAL TABLE records USING fts5(id UNINDEXED, title, tags, body);\n"
    awk '
      function esc(s) { gsub(/\047/, "\047\047", s); return s }
      function fm_value(line,    p) {
        p = index(line, ": ")
        if (p > 0) return substr(line, p + 2)
        return line
      }
      function fm_strip_quotes(val) {
        if (substr(val, 1, 1) == "\042") val = substr(val, 2)
        if (length(val) > 0 && substr(val, length(val), 1) == "\042") val = substr(val, 1, length(val) - 1)
        return val
      }
      function tags_sql(raw,    s) {
        s = raw
        sub(/^\[/, "", s)
        sub(/\]$/, "", s)
        gsub(/, /, ",", s)
        return esc(s)
      }
      function fm_ok(got) {
        return got["id"] && got["kind"] && got["title"] && got["date"] && got["source"] &&
          got["commit"] && got["harness"] && got["tags"] && got["supersedes"] && got["sha256"]
      }
      function emit_insert(path,    line, key, val, c, closed, got, body, fm_id, fm_title, fm_tags, listfile) {
        split("", got)
        c = 0
        closed = 0
        body = ""
        fm_id = ""
        fm_title = ""
        fm_tags = ""
        while ((getline line < path) > 0) {
          sub(/\r$/, "", line)
          if (c == 0) {
            if (line != "---") { close(path); return }
            c = 1
            continue
          }
          if (c == 1) {
            if (line == "---") { closed = 1; c = 2; continue }
            key = line
            sub(/:.*/, "", key)
            val = fm_value(line)
            if (key == "title" || key == "source" || key == "harness") val = fm_strip_quotes(val)
            if (key == "id") { fm_id = val; got["id"] = 1 }
            else if (key == "kind") got["kind"] = 1
            else if (key == "title") { fm_title = val; got["title"] = 1 }
            else if (key == "date") got["date"] = 1
            else if (key == "source") got["source"] = 1
            else if (key == "commit") got["commit"] = 1
            else if (key == "harness") got["harness"] = 1
            else if (key == "tags") { fm_tags = val; got["tags"] = 1 }
            else if (key == "supersedes") got["supersedes"] = 1
            else if (key == "sha256") got["sha256"] = 1
            continue
          }
          if (body == "") body = line
          else body = body sprintf("%c", 10) line
        }
        close(path)
        if (!closed || !fm_ok(got)) return
        printf "INSERT INTO records(id, title, tags, body) VALUES('\''%s'\'','\''%s'\'','\''%s'\'','\''%s'\'');\n",
          esc(fm_id), esc(fm_title), tags_sql(fm_tags), esc(body)
      }
      BEGIN {
        listfile = ENVIRON["MEM_AWK_LISTFILE"]
        while ((getline path < listfile) > 0) {
          if (path == "") continue
          emit_insert(path)
        }
        close(listfile)
      }
    '
  } > "$sql"
  sqlite3 -batch -init /dev/null -noheader "$db" < "$sql" || return 1
  return 0
}

parse_tags_brackets() { # [a, b] → US-separated items in REC_LIST_ITEMS (an item may contain spaces)
  local raw="$1" inner x out=""
  inner="$(printf '%s' "$raw" | sed 's/^\[//;s/\]$//')"
  REC_LIST_ITEMS=""
  [ -n "$inner" ] || return 0
  local rest="$inner"
  while [ -n "$rest" ]; do
    x="${rest%%,*}"
    if [ "$x" = "$rest" ]; then rest=""; else rest="${rest#*,}"; fi
    x="$(trim_ascii_sp "$x")"
    [ -n "$x" ] || continue
    out="${out:+$out$US}$x"
  done
  REC_LIST_ITEMS="$out"
}

parse_supersedes_brackets() {
  parse_tags_brackets "$1"
}

run_index() { # <root> <quiet: 0|1>
  local root="$1" quiet="${2:-0}" store rec_list man stamp n fts_yes=0
  store="$(store_dir "$root")"
  rec_list="$(mk_tmp)"
  man="$store/.index/manifest.tsv"
  stamp="$store/.index/stamp"
  glob_record_files "$store" "$rec_list"

  local sort_in ref_file badfile
  sort_in="$(mk_tmp)"
  ref_file="$(mk_tmp)"
  badfile="$(mk_tmp)"
  : > "$sort_in"
  : > "$ref_file"
  : > "$badfile"
  export MEM_AWK_ROOT="$root"
  export MEM_AWK_LISTFILE="$rec_list"
  export MEM_AWK_SORT_OUT="$sort_in"
  export MEM_AWK_REF_OUT="$ref_file"
  export MEM_AWK_BAD_OUT="$badfile"
  awk '
    function relpath(r, path,    p) {
      p = r "/"
      if (substr(path, 1, length(p)) == p) return substr(path, length(p) + 1)
      gsub(/\\/, "/", path)
      return path
    }
    function fm_value(line,    p) {
      p = index(line, ": ")
      if (p > 0) return substr(line, p + 2)
      return line
    }
    function fm_strip_quotes(val) {
      if (substr(val, 1, 1) == "\042") val = substr(val, 2)
      if (length(val) > 0 && substr(val, length(val), 1) == "\042") val = substr(val, 1, length(val) - 1)
      return val
    }
    function trim_sp(s) { sub(/^ +/, "", s); sub(/ +$/, "", s); return s }
    function brackets_csv(raw,    s, n, parts, i, item, out) {
      s = raw
      sub(/^\[/, "", s)
      sub(/\]$/, "", s)
      if (s == "") return ""
      n = split(s, parts, ",")
      out = ""
      for (i = 1; i <= n; i++) {
        item = trim_sp(parts[i])
        if (item == "") continue
        if (out != "") out = out "," item
        else out = item
      }
      return out
    }
    function fm_ok(got) {
      return got["id"] && got["kind"] && got["title"] && got["date"] && got["source"] &&
        got["commit"] && got["harness"] && got["tags"] && got["supersedes"] && got["sha256"]
    }
    function emit_refs(sup_m, newid,    n, parts, i, ref_out) {
      ref_out = ENVIRON["MEM_AWK_REF_OUT"]
      if (sup_m == "") return
      n = split(sup_m, parts, ",")
      for (i = 1; i <= n; i++) {
        if (parts[i] == "") continue
        printf "%s\t%s\n", parts[i], newid >> ref_out
      }
    }
    function skip_malformed(path,    root, bad_out) {
      root = ENVIRON["MEM_AWK_ROOT"]
      bad_out = ENVIRON["MEM_AWK_BAD_OUT"]
      print relpath(root, path) >> bad_out
    }
    function process_file(path,    line, key, val, c, closed, got, tags_m, sup_m, rel, root, sort_out) {
      split("", got)
      root = ENVIRON["MEM_AWK_ROOT"]
      sort_out = ENVIRON["MEM_AWK_SORT_OUT"]
      c = 0
      closed = 0
      fm_id = ""
      fm_kind = ""
      fm_date = ""
      fm_title = ""
      fm_tags = ""
      fm_sup = ""
      while ((getline line < path) > 0) {
        sub(/\r$/, "", line)
        if (c == 0) {
          if (line != "---") { close(path); skip_malformed(path); return 0 }
          c = 1
          continue
        }
        if (c == 1) {
          if (line == "---") { closed = 1; break }
          key = line
          sub(/:.*/, "", key)
          val = fm_value(line)
          if (key == "title" || key == "source" || key == "harness") val = fm_strip_quotes(val)
          if (key == "id") { fm_id = val; got["id"] = 1 }
          else if (key == "kind") { fm_kind = val; got["kind"] = 1 }
          else if (key == "title") { fm_title = val; got["title"] = 1 }
          else if (key == "date") { fm_date = val; got["date"] = 1 }
          else if (key == "source") got["source"] = 1
          else if (key == "commit") got["commit"] = 1
          else if (key == "harness") got["harness"] = 1
          else if (key == "tags") { fm_tags = val; got["tags"] = 1 }
          else if (key == "supersedes") { fm_sup = val; got["supersedes"] = 1 }
          else if (key == "sha256") got["sha256"] = 1
          continue
        }
      }
      close(path)
      if (!closed || !fm_ok(got)) { skip_malformed(path); return 0 }
      tags_m = brackets_csv(fm_tags)
      sup_m = brackets_csv(fm_sup)
      rel = relpath(root, path)
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", fm_id, fm_kind, fm_date, fm_title, tags_m, rel, sup_m >> sort_out
      emit_refs(sup_m, fm_id)
      return 1
    }
    BEGIN {
      listfile = ENVIRON["MEM_AWK_LISTFILE"]
      while ((getline path < listfile) > 0) {
        if (path == "") continue
        process_file(path)
      }
      close(listfile)
    }
  '
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    printf 'memory: skipped malformed %s\n' "$rel" >&2
  done < "$badfile"
  n="$(wc -l < "$sort_in" | tr -d '[:space:]')"
  n="${n:-0}"

  mkdir -p "$store/.index"
  {
    printf '%s\n' 'id	kind	date	title	tags	path	supersedes	superseded_by'
    export MEM_AWK_REFFILE="$ref_file"
    sort -t '	' -k1,1 "$sort_in" | awk -F'\t' '
      function join_sorted_arr(a, n,    i, j, tmp, out) {
        for (i = 1; i <= n; i++)
          for (j = i + 1; j <= n; j++)
            if (a[i] > a[j]) { tmp = a[i]; a[i] = a[j]; a[j] = tmp }
        out = ""
        for (i = 1; i <= n; i++) {
          if (out != "") out = out "," a[i]
          else out = a[i]
        }
        return out
      }
      BEGIN {
        reffile = ENVIRON["MEM_AWK_REFFILE"]
        while ((getline < reffile) > 0) {
          key = $1 ""
          idx = ++ref_n[key]
          ref_by[key, idx] = $2 ""
        }
        close(reffile)
      }
      {
        rid = $1 ""
        if (!(rid in ref_n)) {
          print $0 "\t"
          next
        }
        nn = ref_n[rid]
        for (i = 1; i <= nn; i++) arr[i] = ref_by[rid, i]
        print $0 "\t" join_sorted_arr(arr, nn)
      }
    '
  } > "$man"

  printf '%s\n' "$n" > "$stamp"

  fts_yes=0
  if fts5_available; then
    fts_yes=1
    export MEM_AWK_LISTFILE="$rec_list"
    if build_fts_db "$store"; then
      :
    else
      rm -f "$store/.index/fts.db"
      fts_yes=0
    fi
  else
    rm -f "$store/.index/fts.db"
  fi

  if [ "$quiet" -eq 0 ]; then
    if [ "$fts_yes" -eq 1 ]; then
      printf 'memory: indexed %s records · fts: yes\n' "$n"
    else
      printf 'memory: indexed %s records · fts: no\n' "$n"
    fi
  fi
}

count_valid_records() { # <store>
  local store="$1" list="$(mk_tmp)" n
  glob_record_files "$store" "$list"
  n=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n + 1))
  done < "$list"
  printf '%s' "$n"
}

index_is_stale() { # <root>
  local root="$1" store man stamp cnt stamp_n f
  store="$(store_dir "$root")"
  man="$store/.index/manifest.tsv"
  stamp="$store/.index/stamp"
  [ -f "$man" ] && [ -f "$stamp" ] || return 0
  cnt="$(count_valid_records "$store")"
  stamp_n="$(tr -d '[:space:]' < "$stamp")"
  [ "$cnt" = "$stamp_n" ] || return 0
  if [ -d "$store/records" ]; then
    local newer_list id
    newer_list="$(mk_tmp)"
    find -L "$store/records" -mindepth 3 -maxdepth 3 -type f -name '*.md' -newer "$man" 2>/dev/null > "$newer_list" || true
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in
        */records/[0-9][0-9][0-9][0-9]/[0-9][0-9]/*.md) ;;
        *) continue ;;
      esac
      id="${f##*/}"; id="${id%.md}"
      valid_record_id "$id" && return 0
    done < "$newer_list"
  fi
  return 1
}

cmd_add() {
  local root="" kind="" title="" body_path="" source="" tags_raw="" sup_raw="" harness=""
  local seen_root=0 seen_kind=0 seen_title=0 seen_body=0 seen_source=0 seen_tags=0 seen_sup=0 seen_harness=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --root) need_val "$@"; [ "$seen_root" -eq 0 ] || die 2 "repeated flag '--root'"; seen_root=1; root="$2"; shift 2 ;;
      --kind) need_val "$@"; [ "$seen_kind" -eq 0 ] || die 2 "repeated flag '--kind'"; seen_kind=1; kind="$2"; shift 2 ;;
      --title) need_val "$@"; [ "$seen_title" -eq 0 ] || die 2 "repeated flag '--title'"; seen_title=1; title="$2"; shift 2 ;;
      --body) need_val "$@"; [ "$seen_body" -eq 0 ] || die 2 "repeated flag '--body'"; seen_body=1; body_path="$2"; shift 2 ;;
      --source) need_val "$@"; [ "$seen_source" -eq 0 ] || die 2 "repeated flag '--source'"; seen_source=1; source="$2"; shift 2 ;;
      --tags) need_val "$@"; [ "$seen_tags" -eq 0 ] || die 2 "repeated flag '--tags'"; seen_tags=1; tags_raw="$2"; shift 2 ;;
      --supersedes) need_val "$@"; [ "$seen_sup" -eq 0 ] || die 2 "repeated flag '--supersedes'"; seen_sup=1; sup_raw="$2"; shift 2 ;;
      --harness) need_val "$@"; [ "$seen_harness" -eq 0 ] || die 2 "repeated flag '--harness'"; seen_harness=1; harness="$2"; shift 2 ;;
      --*) die 2 "unknown flag '$1'" ;;
      *) die 2 "unexpected argument '$1'" ;;
    esac
  done

  [ "$seen_kind" -eq 1 ] || die 2 "'add' requires --kind"
  [ "$seen_title" -eq 1 ] || die 2 "'add' requires --title"
  [ "$seen_body" -eq 1 ] || die 2 "'add' requires --body"

  valid_kind "$kind" || die 2 "invalid --kind"
  if [ "$seen_harness" -eq 1 ]; then
    valid_harness "$harness" || die 2 "invalid --harness"
  fi

  local tlen
  tlen="$(byte_len "$title")"
  [ "$tlen" -ge 1 ] && [ "$tlen" -le 120 ] || die 2 "invalid --title"
  case "$title" in
    *[\"\\]*|*[[:cntrl:]]*) die 2 "invalid --title" ;;
  esac
  case "$source" in
    *[[:cntrl:]]*) die 2 "invalid --source" ;;
  esac

  parse_list "$tags_raw" tag || die 2 "invalid --tags"
  local tags_items="$PARSED_LIST_ITEMS"
  parse_list "$sup_raw" id || die 2 "invalid --supersedes"
  local sup_items="$PARSED_LIST_ITEMS"

  if [ -n "${MEMORY_NOW:-}" ]; then
    re_match "$MEMORY_NOW" "$re_memory_now" || die 2 "invalid MEMORY_NOW"
  fi

  [ "$seen_root" -eq 1 ] || root="$(default_root)"
  root="$(resolve_root "$root")"
  have_sha256 || die 4 "no sha256 tool"
  [ -f "$body_path" ] || die 4 "body file not found: $body_path"

  local body_file sha now id date commit store dup_id rel path
  body_file="$(prepare_body_file "$body_path")"
  sha="$(sha256_hex < "$body_file")"
  if [ -n "${MEMORY_NOW:-}" ]; then
    now="$MEMORY_NOW"
  else
    now="$(utc_now_id_prefix)"
  fi
  id="${now}-${sha:0:8}"
  date="${id:0:4}-${id:4:2}-${id:6:2}"
  commit="$(commit_short "$root")"
  store="$(store_dir "$root")"

  for sid in $sup_items; do
    [ -f "$(id_to_record_path "$store" "$sid")" ] || die 4 "supersedes id not found: $sid"
  done

  local dedupe_list="$(mk_tmp)" f dup_id=""
  glob_dedupe_files "$store" "$dedupe_list"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    read_frontmatter "$f" || {
      printf 'memory: skipped malformed %s\n' "$(relpath_under_root "$root" "$f")" >&2
      continue
    }
    if [ "$FM_SHA256" = "$sha" ]; then
      if [ -z "$dup_id" ] || [ "$FM_ID" \< "$dup_id" ]; then
        dup_id="$FM_ID"
      fi
    fi
  done < "$dedupe_list"
  if [ -n "$dup_id" ]; then
    local dup_path
    if [ -f "$(id_to_record_path "$store" "$dup_id")" ]; then
      dup_path="$(relpath_under_root "$root" "$(id_to_record_path "$store" "$dup_id")")"
    else
      dup_path="$(relpath_under_root "$root" "$(id_to_quarantine_path "$store" "$dup_id")")"
    fi
    printf 'memory: duplicate %s %s\n' "$dup_id" "$dup_path"
    exit 0
  fi

  if admission_violation "$title" "$body_file"; then
    path="$(id_to_quarantine_path "$store" "$id")"
    rel="$(relpath_under_root "$root" "$path")"
    [ -e "$path" ] && die 4 "record exists $rel"
    write_record_file "$path" "$id" "$kind" "$title" "$date" "$source" "$commit" "$harness" \
      "$tags_items" "$sup_items" "$sha" "$body_file" 1
    printf 'memory: quarantined %s %s\n' "$id" "$rel"
    exit 5
  fi

  path="$(id_to_record_path "$store" "$id")"
  rel="$(relpath_under_root "$root" "$path")"
  [ -e "$path" ] && die 4 "record exists $rel"
  write_record_file "$path" "$id" "$kind" "$title" "$date" "$source" "$commit" "$harness" \
    "$tags_items" "$sup_items" "$sha" "$body_file" 0
  printf 'memory: added %s %s\n' "$id" "$rel"
  exit 0
}

cmd_index() {
  local root="" seen_root=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --root) need_val "$@"; [ "$seen_root" -eq 0 ] || die 2 "repeated flag '--root'"; seen_root=1; root="$2"; shift 2 ;;
      --*) die 2 "unknown flag '$1'" ;;
      *) die 2 "unexpected argument '$1'" ;;
    esac
  done
  [ "$seen_root" -eq 1 ] || root="$(default_root)"
  root="$(resolve_root "$root")"
  run_index "$root" 0
  exit 0
}

cmd_show() {
  local root="" id="" seen_root=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --root) need_val "$@"; [ "$seen_root" -eq 0 ] || die 2 "repeated flag '--root'"; seen_root=1; root="$2"; shift 2 ;;
      --*) die 2 "unknown flag '$1'" ;;
      *)
        [ -z "$id" ] || die 2 "unexpected argument '$1'"
        id="$1"
        shift
        ;;
    esac
  done
  [ -n "$id" ] || die 2 "'show' requires id"
  re_match "$id" "$re_id" || die 2 "invalid id"
  [ "$seen_root" -eq 1 ] || root="$(default_root)"
  root="$(resolve_root "$root")"
  local store rec q
  store="$(store_dir "$root")"
  rec="$(id_to_record_path "$store" "$id")"
  q="$(id_to_quarantine_path "$store" "$id")"
  if [ -f "$rec" ]; then
    cat "$rec"
    exit 0
  fi
  if [ -f "$q" ]; then
    cat "$q"
    exit 0
  fi
  die 4 "record not found: $id"
}

cmd_search() {
  local root="" kind_raw="" limit="10" engine="grep" include_sup=0
  local seen_root=0 seen_kind=0 seen_limit=0 seen_engine=0 seen_include=0
  local parsing_flags=1

  TERMS=()
  while [ $# -gt 0 ]; do
    if [ "$parsing_flags" -eq 1 ]; then
      case "$1" in
        --) parsing_flags=0; shift; continue ;;
        --root) need_val "$@"; [ "$seen_root" -eq 0 ] || die 2 "repeated flag '--root'"; seen_root=1; root="$2"; shift 2 ;;
        --kind) need_val "$@"; [ "$seen_kind" -eq 0 ] || die 2 "repeated flag '--kind'"; seen_kind=1; kind_raw="$2"; shift 2 ;;
        --limit) need_val "$@"; [ "$seen_limit" -eq 0 ] || die 2 "repeated flag '--limit'"; seen_limit=1; limit="$2"; shift 2 ;;
        --engine) need_val "$@"; [ "$seen_engine" -eq 0 ] || die 2 "repeated flag '--engine'"; seen_engine=1; engine="$2"; shift 2 ;;
        --include-superseded) [ "$seen_include" -eq 0 ] || die 2 "repeated flag '--include-superseded'"; seen_include=1; include_sup=1; shift ;;
        --*) die 2 "unknown flag '$1'" ;;
        *) TERMS[${#TERMS[@]}]="$1"; shift ;;
      esac
    else
      TERMS[${#TERMS[@]}]="$1"
      shift
    fi
  done

  if [ ${#TERMS[@]} -eq 0 ]; then
    die 2 "search requires at least one term"
  fi
  for t in "${TERMS[@]}"; do
    [ -n "$t" ] || die 2 "empty search term"
  done

  re_match "$limit" "$re_limit" || die 2 "invalid --limit"
  [ "${#limit}" -le 3 ] || die 2 "invalid --limit"
  [ "$limit" -le 100 ] || die 2 "invalid --limit"

  case "$engine" in
    grep|fts) ;;
    *) die 2 "invalid --engine" ;;
  esac

  local kind_filter=""
  if [ "$seen_kind" -eq 1 ]; then
    parse_list "$kind_raw" kind || die 2 "invalid --kind"
    kind_filter="$PARSED_LIST_ITEMS"
    [ -n "$kind_filter" ] || die 2 "invalid --kind"
  fi

  [ "$seen_root" -eq 1 ] || root="$(default_root)"
  root="$(resolve_root "$root")"

  if index_is_stale "$root"; then
    run_index "$root" 1
  fi

  local store man
  store="$(store_dir "$root")"
  man="$store/.index/manifest.tsv"
  [ -f "$man" ] || run_index "$root" 1

  if [ "$engine" = "fts" ]; then
    fts5_available || die 4 "fts engine unavailable"
    [ -f "$store/.index/fts.db" ] || die 4 "fts engine unavailable"
  fi

  local cand="$(mk_tmp)" i=0 ti
  export MEM_NTERMS="${#TERMS[@]}"
  for ti in "${TERMS[@]}"; do
    i=$((i + 1))
    export "MEMTERM_$i=$ti"
  done
  export MEM_AWK_ROOT="$root"
  export MEM_INCLUDE_SUP="$include_sup"
  export MEM_AWK_KINDS="$kind_filter"
  tail -n +2 "$man" | awk -F'\t' '
    function foldline(s,    i, ch, out) {
      out = ""
      for (i = 1; i <= length(s); i++) {
        ch = substr(s, i, 1)
        if (ch >= "A" && ch <= "Z") ch = tolower(ch)
        out = out ch
      }
      return out
    }
    function fm_value(line,    p) {
      p = index(line, ": ")
      if (p > 0) return substr(line, p + 2)
      return line
    }
    function fm_strip_quotes(val) {
      if (substr(val, 1, 1) == "\042") val = substr(val, 2)
      if (length(val) > 0 && substr(val, length(val), 1) == "\042") val = substr(val, 1, length(val) - 1)
      return val
    }
    function trim_sp(s) { sub(/^ +/, "", s); sub(/ +$/, "", s); return s }
    function brackets_csv(raw,    s, n, parts, i, item, out) {
      s = raw
      sub(/^\[/, "", s)
      sub(/\]$/, "", s)
      if (s == "") return ""
      n = split(s, parts, ",")
      out = ""
      for (i = 1; i <= n; i++) {
        item = trim_sp(parts[i])
        if (item == "") continue
        if (out != "") out = out "," item
        else out = item
      }
      return out
    }
    function fm_ok(got) {
      return got["id"] && got["kind"] && got["title"] && got["date"] && got["source"] &&
        got["commit"] && got["harness"] && got["tags"] && got["supersedes"] && got["sha256"]
    }
    function kind_ok(k,    n, i, ka, kinds) {
      kinds = ENVIRON["MEM_AWK_KINDS"]
      if (kinds == "") return 1
      n = split(kinds, ka, " ")
      for (i = 1; i <= n; i++) if (ka[i] == k) return 1
      return 0
    }
    function meta_hit(title, tags_csv, term_f,    title_f, n, parts, i, tag_f) {
      title_f = foldline(title)
      if (index(title_f, term_f) > 0) return 1
      if (tags_csv == "") return 0
      n = split(tags_csv, parts, ",")
      for (i = 1; i <= n; i++) {
        tag_f = foldline(trim_sp(parts[i]))
        if (index(tag_f, term_f) > 0) return 1
      }
      return 0
    }
    function score_file(path,    line, key, val, c, closed, got, fm_title, fm_tags_raw, tags_csv, total, ti, term_f, bh, line_f, fi) {
      split("", got)
      c = 0
      closed = 0
      fm_title = ""
      fm_tags_raw = ""
      for (ti = 1; ti <= nt; ti++) bh[ti] = 0
      while ((getline line < path) > 0) {
        sub(/\r$/, "", line)
        if (c == 0) {
          if (line != "---") { close(path); return -1 }
          c = 1
          continue
        }
        if (c == 1) {
          if (line == "---") { closed = 1; c = 2; continue }
          key = line
          sub(/:.*/, "", key)
          val = fm_value(line)
          if (key == "title" || key == "source" || key == "harness") val = fm_strip_quotes(val)
          if (key == "id") got["id"] = 1
          else if (key == "kind") got["kind"] = 1
          else if (key == "title") { fm_title = val; got["title"] = 1 }
          else if (key == "date") got["date"] = 1
          else if (key == "source") got["source"] = 1
          else if (key == "commit") got["commit"] = 1
          else if (key == "harness") got["harness"] = 1
          else if (key == "tags") { fm_tags_raw = val; got["tags"] = 1 }
          else if (key == "supersedes") got["supersedes"] = 1
          else if (key == "sha256") got["sha256"] = 1
          continue
        }
        line_f = foldline(line)
        for (ti = 1; ti <= nt; ti++) {
          if (index(line_f, terms[ti]) > 0) bh[ti]++
        }
      }
      close(path)
      if (c == 0 || !closed || !fm_ok(got)) return -1
      tags_csv = brackets_csv(fm_tags_raw)
      total = 0
      for (ti = 1; ti <= nt; ti++) {
        term_f = terms[ti]
        if (meta_hit(fm_title, tags_csv, term_f)) total += 3
        total += bh[ti]
      }
      return total
    }
    BEGIN {
      nt = ENVIRON["MEM_NTERMS"] + 0
      for (i = 1; i <= nt; i++) {
        terms[i] = ENVIRON["MEMTERM_" i]
        terms[i] = foldline(terms[i])
      }
    }
    {
      rid = $1
      rkind = $2
      rdate = $3
      rtitle = $4
      rtags = $5
      rpath = $6
      rsup = $7
      rsby = $8
      for (fi = 9; fi <= NF; fi++) rsby = rsby "\t" $fi
      include_sup = ENVIRON["MEM_INCLUDE_SUP"] + 0
      if (include_sup == 0 && rsby != "") next
      if (!kind_ok(rkind)) next
      fpath = ENVIRON["MEM_AWK_ROOT"] "/" rpath
      score = score_file(fpath)
      if (score < 0) next
      if (score + 0 <= 0) next
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", rid, rkind, rdate, score, rtitle, rpath, score
    }
  ' > "$cand"

  if [ ! -s "$cand" ]; then
    die 0 "0 results"
  fi

  local out sorted ranked
  out="$(mk_tmp)"
  if [ "$engine" = "grep" ]; then
    sorted="$(mk_tmp)"
    sort -t '	' -k4,4nr -k1,1r "$cand" > "$sorted"
    head -n "$limit" "$sorted" | awk -F'\t' 'NF >= 6 {
      printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, $4, $5, $6
    }' > "$out"
  else
    local match_parts="" term esc sql qfile
    for term in "${TERMS[@]}"; do
      esc="$(printf '%s' "$term" | sed 's/"/""/g')"
      match_parts="${match_parts}${match_parts:+ OR }\"$esc\""
    done
    sql="$(mk_tmp)"
    qfile="$(mk_tmp)"
    {
      printf "SELECT id, bm25(records) FROM records WHERE records MATCH '%s';\n" "$(sql_escape_sq "$match_parts")"
    } > "$sql"
    if sqlite3 -batch -init /dev/null -noheader -separator "$TAB" "$store/.index/fts.db" < "$sql" > "$qfile" 2>/dev/null; then
      :
    else
      : > "$qfile"
    fi
    ranked="$(mk_tmp)"
    export MEM_AWK_QFILE="$qfile"
    awk -F'\t' '
      BEGIN {
        qf = ENVIRON["MEM_AWK_QFILE"]
        while ((getline line < qf) > 0) {
          split(line, f, "\t")
          k = f[1] ""
          if (!(k in bm)) bm[k] = f[2]
        }
        close(qf)
      }
      {
        cid = $1 ""
        if (cid in bm) printf "0\t%s\t%s\n", bm[cid], $0
        else printf "1\t0\t%s\n", $0
      }
    ' "$cand" > "$ranked"
    sorted="$(mk_tmp)"
    sort -t '	' -k1,1n -k2,2g -k3,3r "$ranked" > "$sorted"
    head -n "$limit" "$sorted" | awk -F'\t' 'NF >= 8 {
      printf "%s\t%s\t%s\t%s\t%s\t%s\n", $3, $4, $5, $6, $7, $8
    }' > "$out"
  fi

  if [ ! -s "$out" ]; then
    die 0 "0 results"
  fi
  cat "$out"
  exit 0
}

# --- main ---
[ $# -eq 0 ] && { usage >&2; exit 2; }

case "$1" in
  --help)
    usage
    exit 0
    ;;
esac

sub="$1"
shift

case "$sub" in
  --help)
    usage
    exit 0
    ;;
  add|index|search|show) ;;
  *)
    usage >&2
    die 2 "unknown subcommand '$sub'"
    ;;
esac

if [ $# -gt 0 ]; then
  case "$1" in
    --help)
      usage
      exit 0
      ;;
  esac
fi

case "$sub" in
  add) cmd_add "$@" ;;
  index) cmd_index "$@" ;;
  search) cmd_search "$@" ;;
  show) cmd_show "$@" ;;
esac
