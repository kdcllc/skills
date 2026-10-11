# shellcheck shell=bash
# kit_version FILE — prints the kit version recorded in FILE.
# A SKILL.md (first line `---`) yields its frontmatter metadata.version; any
# other file yields its content with whitespace stripped (mutation fixtures
# write a bare version string).
kit_version() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  if [[ "$(head -n 1 "$file")" == "---" ]]; then
    awk '
      NR == 1 { next }
      /^---$/ { exit }
      /^metadata:/ { m = 1; next }
      m && /^[^ \t]/ { exit }
      m && $1 == "version:" { v = $2; gsub(/["\047]/, "", v); print v; exit }
    ' "$file"
  else
    tr -d '[:space:]' < "$file"
  fi
}
