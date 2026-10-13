# Sourced from tests/agent-kit/templates/memory.sh (bash leg only).
# Uses caller report, mktemp_dir, mktemp_root, MEMORY_SH, MEMORY_PS1, REPO_ROOT, CANON_MEMORY_SH.

run_release_c_bash_only() {
  local R="" B="" T="" out="" rc=0 id="" p="" mut="" mutsh="" n=0 RC_MEMORY_SH=""
  RC_MEMORY_SH="$MEMORY_SH"
  mktemp_dir T
  mktemp_dir B

  rc_fresh() { # tag
    n=$((n + 1))
    R="$T/r$n"
    mkdir -p "$R"
    git -C "$R" init -q
  }

  rc_git() { git -C "$R" -c user.email=e@x -c user.name=n "$@"; }

  rc_add() { # MEMORY_NOW body
    printf '%b' "$2" > "$B/body"
    MEMORY_NOW="$1" bash "$MEMORY_SH" add --kind fact --title "t$n" --body "$B/body" --root "$R" 2>/dev/null | awk '{print $4}'
  }

  rc_fixsha() {
    local f="$1" s
    s="$(awk 'c>=2{print} /^---$/{c++}' "$f" | sha256sum | cut -d' ' -f1)"
    awk -v s="$s" 'c<2{ if ($0 ~ /^sha256: /) print "sha256: " s; else print; if ($0=="---") c++; next } {print}' "$f" > "$f.n" && mv "$f.n" "$f"
  }

  rc_chk() { # name args...
    local name="$1" out2="" rc2=0
    shift
    out2="$(bash "$RC_MEMORY_SH" check "$@" --root "$R" 2>&1)"; rc2=$?
    case "$name" in
      empty-ok) [[ "$rc2" -eq 0 && "$out2" == 'memory: check ok 0 file(s)' ]] && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2 out=$out2" ;;
      clean-ok|path-ok|admission-quar-ok) [[ "$rc2" -eq 0 && "$out2" == 'memory: check ok 1 file(s)' ]] \
        && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2 out=$out2" ;;
      *-ok|staged-D-quar-A-record-ok|staged-D-quarantine-ok|subdir-staged-clean) \
        [[ "$rc2" -eq 0 && "$out2" == *'check ok'* ]] && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2 out=$out2" ;;
      *title-body-secret*) [[ "$rc2" -eq 3 && "$(grep -c 'check failed secret' <<<"$out2")" -eq 1 ]] \
        && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2 out=$out2" ;;
      *secret*) [[ "$rc2" -eq 3 && "$out2" == *'check failed secret'* ]] && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2 out=$out2" ;;
      *immutable*) [[ "$rc2" -eq 3 && "$out2" == *'check failed immutable'* ]] && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2 out=$out2" ;;
      *two-reasons*) local sl="" tl=""
        sl="$(grep -n 'check failed sha256-mismatch' <<<"$out2" | head -1 | cut -d: -f1)"
        tl="$(grep -n 'check failed secret' <<<"$out2" | head -1 | cut -d: -f1)"
        [[ "$rc2" -eq 3 && -n "$sl" && -n "$tl" && "$sl" -lt "$tl" && "$(grep -c 'check failed' <<<"$out2")" -eq 2 ]] \
        && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2 out=$out2 sl=$sl tl=$tl" ;;
      *outside*) [[ "$rc2" -eq 2 ]] && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2" ;;
      *malformed*) [[ "$rc2" -eq 3 && "$out2" == *'check failed malformed'* ]] && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2 out=$out2" ;;
      *id-mismatch*) [[ "$rc2" -eq 3 && "$out2" == *'check failed id-mismatch'* ]] && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2 out=$out2" ;;
      *sha256*) [[ "$rc2" -eq 3 && "$out2" == *'check failed sha256-mismatch'* ]] && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2 out=$out2" ;;
      *admission-rec*) [[ "$rc2" -eq 3 && "$out2" == *'check failed admission'* ]] && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2 out=$out2" ;;
      *admission-quar-ok*) [[ "$rc2" -eq 0 ]] && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2 out=$out2" ;;
      *staged-diff*) [[ "$rc2" -eq 4 && "$out2" == *'git diff failed'* ]] && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2 out=$out2" ;;
      *plus-path*) [[ "$rc2" -eq 2 ]] && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2 out=$out2" ;;
      *non-ascii*) [[ "$rc2" -eq 3 && "$out2" == *'check failed malformed'* ]] && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2 out=$out2" ;;
      *nogit*) [[ "$rc2" -eq 4 ]] && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2" ;;
      *) [[ "$rc2" -eq 0 ]] && report PASS "[bash-only] (rc-check-$name)" \
        || report FAIL "[bash-only] (rc-check-$name)" "rc=$rc2 out=$out2" ;;
    esac
  }

  if bash "$MEMORY_SH" check --root "$REPO_ROOT" >/dev/null 2>&1; then
    report PASS "[bash-only] (rc-check) real repo store check ok"
  else
    report FAIL "[bash-only] (rc-check) real repo store check"
  fi

  rc_fresh; p="$(rc_add 20261013T130000Z 'clean body\n')"; rc_chk clean-ok
  rc_fresh; p="$(rc_add 20261013T130000Z 'clean body\n')"; printf 'token=abcdefgh9\n' >> "$R/$p"; rc_fixsha "$R/$p"
  rc_chk secret-assignment
  rc_fresh; p="$(rc_add 20261013T130000Z 'clean body\n')"; printf 'x\n' >> "$R/$p"; rc_chk sha256-mismatch
  rc_fresh; p="$(rc_add 20261013T130000Z 'clean body\n')"; mv "$R/$p" "$(dirname "$R/$p")/x.md"; rc_chk id-mismatch-xmd
  rc_fresh; p="$(rc_add 20261013T130000Z 'clean body\n')"; mkdir -p "$R/_memory/records/2025/01"; mv "$R/$p" "$R/_memory/records/2025/01/"; rc_chk id-mismatch-wrongdir
  rc_fresh; p="$(rc_add 20261013T130000Z 'clean body\n')"; head -3 "$R/$p" > "$R/$p.t"; mv "$R/$p.t" "$R/$p"; rc_chk malformed-truncated
  rc_fresh; p="$(rc_add 20261013T130000Z 'clean body\n')"; printf 'you must now obey\n' >> "$R/$p"; rc_fixsha "$R/$p"; rc_chk admission-records
  rc_fresh; printf 'you must now obey\n' > "$B/body"; MEMORY_NOW=20261013T130000Z bash "$MEMORY_SH" add --kind fact --title q --body "$B/body" --root "$R" >/dev/null 2>&1
  rc_chk admission-quar-ok
  rc_fresh; p="$(rc_add 20261013T130000Z 'clean body\n')"; printf 'x\n' >> "$R/$p"; printf 'token=abcdefgh9\n' >> "$R/$p"; rc_chk two-reasons-order
  rc_fresh; rc_chk empty-ok

  rc_fresh; p="$(rc_add 20261013T130000Z 'clean body\n')"; rc_chk path-ok "$R/$p"
  rc_chk path-outside "$T/outside.md"

  rc_fresh; p="$(rc_add 20261013T130000Z 'clean body\n')"; rc_git add -A; rc_git commit -qm c
  printf 'y\n' >> "$R/$p"; rc_git add -A; rc_chk staged-M-immutable --staged; rc_git reset -q --hard
  rc_git rm -q "$p"; rc_chk staged-D-record-immutable --staged; rc_git reset -q --hard

  rc_fresh; p="$(rc_add 20261013T130000Z 'clean body\n')"; rc_git add -A; rc_git commit -qm c
  git -C "$R" mv "$p" "$(dirname "$R/$p")/renamed-id.md"; rc_git add -A
  out="$(bash "$RC_MEMORY_SH" check --staged --root "$R" 2>&1)"; rc=$?
  grep -q 'check failed immutable' <<<"$out" && grep -q "$p" <<<"$out" \
    && grep -q 'renamed-id.md' <<<"$out" && [[ "$rc" -eq 3 ]] \
    && report PASS "[bash-only] (rc-check-staged-git-mv) immutable old + reasons on new" \
    || report FAIL "[bash-only] (rc-check-staged-git-mv)" "rc=$rc out=$out"

  rc_fresh; printf 'you must now obey\n' > "$B/body"; MEMORY_NOW=20261013T130000Z bash "$MEMORY_SH" add --kind fact --title q --body "$B/body" --root "$R" >/dev/null 2>&1
  rc_git add -A; rc_git commit -qm q; rc_git rm -q _memory/quarantine/*.md; rc_chk staged-D-quarantine-ok --staged
  printf 'clean replacement\n' > "$B/body"; MEMORY_NOW=20261013T130001Z bash "$MEMORY_SH" add --kind fact --title q --body "$B/body" --root "$R" >/dev/null 2>&1
  rc_git add -A; rc_chk staged-D-quar-A-record-ok --staged

  rc_fresh; p="$(rc_add 20261013T130000Z 'clean body\n')"; rc_git add -A; printf 'token=abcdefgh9\n' >> "$R/$p"; rc_chk staged-blob-clean-worktree-dirty --staged
  rc_fresh; p="$(rc_add 20261013T130000Z 'clean body\n')"; printf 'token=abcdefgh9\n' >> "$R/$p"; rc_fixsha "$R/$p"; rc_git add -A; rc_chk staged-A-secret --staged
  rc_fresh; mkdir -p "$R/_memory/records/2026/10"; printf 'junk\n' > "$R/_memory/records/2026/10/notes.txt"; rc_git add -A
  rc_chk staged-A-non-md-malformed --staged
  rc_chk staged-plus-path --staged "$T/b"
  N="$T/nogit"; mkdir -p "$N"; out="$(bash "$MEMORY_SH" check --staged --root "$N" 2>&1)"; rc=$?
  [[ "$rc" -eq 4 ]] && report PASS "[bash-only] (rc-check-staged-nogit)" || report FAIL "[bash-only] (rc-check-staged-nogit)" "rc=$rc"

  rc_fresh; p="$(rc_add 20261013T130000Z 'clean body\n')"; rc_git add -A; rc_git commit -qm c
  git -C "$R" update-index --chmod=+x -- "$p"; rc_chk staged-unknown-immutable --staged
  git -C "$R" rm -rf .git/index 2>/dev/null || true; printf 'x' > "$R/.git/index"
  out="$(bash "$MEMORY_SH" check --staged --root "$R" 2>&1)"; rc=$?
  [[ "$rc" -eq 4 && "$out" == *'git diff failed'* ]] && report PASS "[bash-only] (rc-check-staged-diff)" \
    || report FAIL "[bash-only] (rc-check-staged-diff)" "rc=$rc out=$out"

  R0="$T/top"; mkdir -p "$R0/sub"; git -C "$R0" init -q; R="$R0/sub"; p="$(rc_add 20261013T130000Z 'clean body\n')"; git -C "$R0" add -A
  out="$(bash "$MEMORY_SH" check --staged --root "$R" 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] && report PASS "[bash-only] (rc-check-subdir-staged-clean)" || report FAIL "[bash-only] (rc-check-subdir-staged-clean)" "rc=$rc"
  p2="$(rc_add 20261013T130001Z 'other\n')"; printf 'token=abcdefgh9\n' >> "$R/$p2"; rc_fixsha "$R/$p2"; git -C "$R0" add -A
  out="$(bash "$MEMORY_SH" check --staged --root "$R" 2>&1)"; rc=$?
  [[ "$rc" -eq 3 && "$out" == *secret* ]] && report PASS "[bash-only] (rc-check-subdir-staged-secret)" \
    || report FAIL "[bash-only] (rc-check-subdir-staged-secret)" "rc=$rc out=$out"

  rc_fresh; mkdir -p "$R/_memory/records/2026/10"; printf 'x\n' > "$R/_memory/records/2026/10/ü.md"; rc_git add -A
  rc_chk staged-non-ascii --staged

  rc_fresh; printf 'body password=abcdefgh9\n' > "$B/body"
  MEMORY_NOW=20261013T130000Z bash "$MEMORY_SH" add --kind fact --title 'clean' --body "$B/body" --root "$R" >/dev/null 2>&1
  f="$(find "$R/_memory/records" -name '*.md' | head -1)"
  sed 's/^title: "clean"$/title: "token=abcdefgh9"/' "$f" > "$f.n" && mv "$f.n" "$f"
  printf 'password=zzzzzzzz9\n' >> "$f"; rc_fixsha "$f"
  rc_chk title-body-secret-one-line
  rc_fresh
  p="$(rc_add 20261013T130010Z 'clean one\n')"
  p2="$(rc_add 20261013T130011Z 'clean two\n')"
  printf 'token=abcdefgh9\n' >> "$R/$p"
  printf 'token=abcdefgh9\n' >> "$R/$p2"
  out="$(bash "$RC_MEMORY_SH" check "$R/$p" "$R/$p2" --root "$R" 2>&1)"; rc=$?
  if [[ "$rc" -eq 3 && "$(grep -c 'check failed secret' <<<"$out")" -eq 2 ]]; then
    [[ "$rc" -eq 3 && "$(grep -c 'check failed secret' <<<"$out")" -eq 1 ]] \
      && report FAIL "[bash-only] (rc-check-title-body-secret-proof)" "one-line arm would pass with two secret lines" \
      || report PASS "[bash-only] (rc-check-title-body-secret-proof) one-line arm active (two secret lines)"
  else
    report FAIL "[bash-only] (rc-check-title-body-secret-proof)" "rc=$rc out=$out"
  fi

  rc_fresh; printf 'password=abcdefgh9\n' > "$B/red.md"
  out="$(MEMORY_NOW=20261013T140002Z bash "$MEMORY_SH" add --kind fact --title 'token=abcdefgh12' --body "$B/red.md" --root "$R" 2>&1)"
  p="$(find "$R/_memory/records" -name '*.md' | tail -1)"
  grep -q 'memory: redacted' <<<"$out" && grep -q '\[REDACTED:secret\]' "$p" \
    && report PASS "[bash-only] (rc-redact-add) add redaction stderr + body" \
    || report FAIL "[bash-only] (rc-redact-add)"

  rc_fresh; p="$(rc_add 20261013T140000Z 'clean body\n')"; printf 'token=abcdefgh9\n' >> "$R/$p"
  out="$(bash "$MEMORY_SH" check "$p" --root "$R" 2>&1)"; rc=$?
  [[ "$rc" -eq 3 && "$out" == *'check failed secret'* ]] \
    && report PASS "[bash-only] (rc-secret) check secret exit 3" \
    || report FAIL "[bash-only] (rc-secret)" "rc=$rc out=$out"

  id="$(basename "$p" .md)"
  bash "$MEMORY_SH" rm "$id" --root "$R" >/dev/null 2>&1
  [[ ! -f "$R/$p" ]] && report PASS "[bash-only] (rc-rm) rm untracked ok" || report FAIL "[bash-only] (rc-rm) untracked"
  MEMORY_NOW=20261013T140001Z bash "$MEMORY_SH" add --kind fact --title tr --body "$B/body" --root "$R" >/dev/null 2>&1
  p="$(find "$R/_memory/records" -name '*.md' | head -1)"; id="$(basename "$p" .md)"
  git -C "$R" add -A && git -C "$R" -c user.email=e@x -c user.name=n commit -qm x
  bash "$MEMORY_SH" rm "$id" --root "$R" >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 2 ]] && report PASS "[bash-only] (rc-rm-tracked) tracked rm exit 2" \
    || report FAIL "[bash-only] (rc-rm-tracked)" "rc=$rc"
  bash "$MEMORY_SH" rm 20261013T100009Z-00000000 --root "$R" >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 4 ]] && report PASS "[bash-only] (rc-rm-missing) missing rm exit 4" || report FAIL "[bash-only] (rc-rm-missing)" "rc=$rc"
  bash "$MEMORY_SH" rm notanid --root "$R" >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 2 ]] && report PASS "[bash-only] (rc-rm-invalid) invalid id exit 2" || report FAIL "[bash-only] (rc-rm-invalid)" "rc=$rc"
  bash "$MEMORY_SH" rm "$id" --root "$N" >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 4 ]] && report PASS "[bash-only] (rc-rm-nogit) non-git rm exit 4" || report FAIL "[bash-only] (rc-rm-nogit)" "rc=$rc"

  rc_fresh; p="$(rc_add 20261013T140002Z 'rm ls-files body\n')"; id="$(basename "$p" .md)"
  git -C "$R" rm -rf .git/index 2>/dev/null || true; printf 'x' > "$R/.git/index"
  err="$(bash "$MEMORY_SH" rm "$id" --root "$R" 2>&1 >/dev/null)"; rc=$?
  [[ "$rc" -eq 4 && "$err" == 'memory: rm: git ls-files failed' && -f "$R/$p" ]] \
    && report PASS "[bash-only] (rc-rm-lsfiles-fatal) corrupt index exit 4 keeps record" \
    || report FAIL "[bash-only] (rc-rm-lsfiles-fatal)" "rc=$rc err=[$err] exists=$([[ -f "$R/$p" ]] && echo yes || echo no)"

  if command -v pwsh >/dev/null 2>&1; then
    local stub_chk stub_rm stub_cap
    stub_chk='memory: '\''check'\'' is bash-only; run bash _kit/memory.sh check (Windows: _kit\memory.cmd check)'
    stub_rm='memory: '\''rm'\'' is bash-only; run bash _kit/memory.sh rm (Windows: _kit\memory.cmd rm)'
    stub_cap='memory: '\''capture'\'' is bash-only; run bash _kit/memory.sh capture (Windows: _kit\memory.cmd capture)'
    out="$(pwsh -NoProfile -NonInteractive -File "$MEMORY_PS1" check 2>&1)"; rc=$?
    [[ "$rc" -eq 2 && "$out" == "$stub_chk" ]] && report PASS "[bash-only] (rc-pwsh-stub-check)" \
      || report FAIL "[bash-only] (rc-pwsh-stub-check)" "rc=$rc out=[$out]"
    out="$(pwsh -NoProfile -NonInteractive -File "$MEMORY_PS1" rm x 2>&1)"; rc=$?
    [[ "$rc" -eq 2 && "$out" == "$stub_rm" ]] && report PASS "[bash-only] (rc-pwsh-stub-rm)" \
      || report FAIL "[bash-only] (rc-pwsh-stub-rm)" "rc=$rc out=[$out]"
    out="$(pwsh -NoProfile -NonInteractive -File "$MEMORY_PS1" capture 2>&1)"; rc=$?
    [[ "$rc" -eq 2 && "$out" == "$stub_cap" ]] && report PASS "[bash-only] (rc-pwsh-stub-capture)" \
      || report FAIL "[bash-only] (rc-pwsh-stub-capture)" "rc=$rc out=[$out]"
  else
    report SKIP "[bash-only] (rc-pwsh-stub) pwsh absent"
  fi

  run_release_c_mutations "$B" "$T"
}

run_release_c_mutations() {
  local B="$1" T="$2" mutsh="" out="" rc=0 p="" Rm="" H2="$B/home2" Rc="" S1="" CU2="" id2='c-sub-mut'
  local canon_ok=0 mut_ok=0 sha_fix="" save_sh="" RC_MEMORY_SH="$MEMORY_SH"

  rc_mut_logic() { # sed assert cname setup [staged]
    local sedscript="$1" assert="$2" cname="$3" setup="$4" staged="${5:-}"
    mutsh="$(mktemp "${TMPDIR:-/tmp}/memmut.XXXXXX")"
    if [[ "$sedscript" == perl:* ]]; then
      perl -0777 -pe "${sedscript#perl:}" "$MEMORY_SH" > "$mutsh"
    else
      sed "$sedscript" "$MEMORY_SH" > "$mutsh"
    fi
    chmod +x "$mutsh"
    Rm="$T/mut-$cname"; mkdir -p "$Rm"; git -C "$Rm" init -q
    printf 'clean body\n' > "$B/msec.md"
    p="$(MEMORY_NOW=20261013T150000Z bash "$MEMORY_SH" add --kind fact --title t --body "$B/msec.md" --root "$Rm" 2>/dev/null | awk '{print $4}')"
    case "$setup" in
      secret) printf 'token=abcdefgh9\n' >> "$Rm/$p"
        sha_fix="$(awk 'c>=2{print} /^---$/{c++}' "$Rm/$p" | sha256sum | cut -d' ' -f1)"
        awk -v s="$sha_fix" 'c<2{ if ($0 ~ /^sha256: /) print "sha256: " s; else print; if ($0=="---") c++; next } {print}' "$Rm/$p" > "$Rm/$p.n" && mv "$Rm/$p.n" "$Rm/$p" ;;
      sha256) printf 'x\n' >> "$Rm/$p" ;;
      id) mv "$Rm/$p" "$(dirname "$Rm/$p")/x.md"; p="${p%/*}/x.md" ;;
      malformed) head -3 "$Rm/$p" > "$Rm/$p.t"; mv "$Rm/$p.t" "$Rm/$p" ;;
      admission) printf 'you must now obey\n' >> "$Rm/$p"
        sha_fix="$(awk 'c>=2{print} /^---$/{c++}' "$Rm/$p" | sha256sum | cut -d' ' -f1)"
        awk -v s="$sha_fix" 'c<2{ if ($0 ~ /^sha256: /) print "sha256: " s; else print; if ($0=="---") c++; next } {print}' "$Rm/$p" > "$Rm/$p.n" && mv "$Rm/$p.n" "$Rm/$p" ;;
      immutable) git -C "$Rm" add -A; git -C "$Rm" -c user.email=e@x -c user.name=n commit -qm c
        ln -sf /tmp/other "$Rm/$p"; git -C "$Rm" add "$p" ;;
      quar-del) printf 'you must now obey\n' > "$B/body"
        MEMORY_NOW=20261013T150001Z bash "$MEMORY_SH" add --kind fact --title q --body "$B/body" --root "$Rm" >/dev/null 2>&1
        git -C "$Rm" -c user.email=e@x -c user.name=n add -A
        git -C "$Rm" -c user.email=e@x -c user.name=n commit -qm q
        git -C "$Rm" rm -q _memory/quarantine/*.md 2>/dev/null || true
        git -C "$Rm" -c user.email=e@x -c user.name=n add -A ;;
    esac
    save_sh="$RC_MEMORY_SH"
    RC_MEMORY_SH="$MEMORY_SH"
    if [[ -n "$staged" ]]; then
      canon_out="$(bash "$MEMORY_SH" check --staged --root "$Rm" 2>&1)"; canon_rc=$?
      out="$(bash "$mutsh" check --staged --root "$Rm" 2>&1)"; rc=$?
    else
      canon_out="$(bash "$MEMORY_SH" check "$Rm/$p" --root "$Rm" 2>&1)"; canon_rc=$?
      out="$(bash "$mutsh" check "$Rm/$p" --root "$Rm" 2>&1)"; rc=$?
    fi
    RC_MEMORY_SH="$save_sh"
    rm -f "$mutsh"
    case "$cname" in
      *secret*) canon_ok=$([[ "$canon_rc" -eq 3 && "$canon_out" == *secret* ]] && echo 1 || echo 0)
        mut_ok=$([[ "$rc" -eq 3 && "$out" == *secret* ]] && echo 1 || echo 0) ;;
      *sha256*) canon_ok=$([[ "$canon_rc" -eq 3 && "$canon_out" == *sha256-mismatch* ]] && echo 1 || echo 0)
        mut_ok=$([[ "$rc" -eq 3 && "$out" == *sha256-mismatch* ]] && echo 1 || echo 0) ;;
      *quarantine*) canon_ok=$([[ "$canon_rc" -eq 0 ]] && echo 1 || echo 0)
        mut_ok=$([[ "$rc" -eq 0 ]] && echo 1 || echo 0) ;;
      *id-mismatch*) canon_ok=$([[ "$canon_rc" -eq 3 && "$canon_out" == *id-mismatch* ]] && echo 1 || echo 0)
        mut_ok=$([[ "$rc" -eq 3 && "$out" == *id-mismatch* ]] && echo 1 || echo 0) ;;
      *malformed*) canon_ok=$([[ "$canon_rc" -eq 3 && "$canon_out" == *malformed* ]] && echo 1 || echo 0)
        mut_ok=$([[ "$rc" -eq 3 && "$out" == *malformed* ]] && echo 1 || echo 0) ;;
      *admission*) canon_ok=$([[ "$canon_rc" -eq 3 && "$canon_out" == *admission* ]] && echo 1 || echo 0)
        mut_ok=$([[ "$rc" -eq 3 && "$out" == *admission* ]] && echo 1 || echo 0) ;;
      *immutable*) canon_ok=$([[ "$canon_rc" -eq 3 && "$canon_out" == *immutable* ]] && echo 1 || echo 0)
        mut_ok=$([[ "$rc" -eq 3 && "$out" == *immutable* ]] && echo 1 || echo 0) ;;
      *) canon_ok=$([[ "$canon_rc" -ne 0 ]] && echo 1 || echo 0); mut_ok=$([[ "$rc" -eq 0 ]] && echo 1 || echo 0) ;;
    esac
    if [[ "$canon_ok" -eq 1 && "$mut_ok" -eq 0 ]]; then
      report PASS "$assert"
    else
      report FAIL "$assert" "canon_rc=$canon_rc rc=$rc canon=[$canon_out] mut=[$out]"
    fi
  }

  rc_mut_logic 's/if \[ "$body_sha" != "$FM_SHA256" \]; then/if false; then # skip sha/' \
    'mutation-check-skip-sha: rc_chk sha256-mismatch' sha256-mismatch sha256
  rc_mut_logic 's/if \[ "$in_records" -eq 1 \] && admission_violation/if false \&\& admission_violation/' \
    'mutation-check-skip-admission: rc_chk admission-records' admission-records admission
  rc_mut_logic 's/_memory\/quarantine\/\*) continue ;;/_memory\/quarantine\/*) check_emit_fail immutable "$rel"; fail=1; continue ;;/' \
    'mutation-check-quarantine-D-immutable: rc_chk staged-D-quarantine-ok' staged-D-quarantine-ok quar-del staged
  rc_mut_logic 'perl:s/A\|M\) ;;\n        \*\)\n          check_emit_fail immutable "\$rel"\n          fail=1\n          continue\n          ;;/A|M) ;;\n        X) continue # unknown disabled\n          ;;/s' \
    'mutation-check-skip-unknown-status: rc_chk staged-unknown-immutable' staged-unknown-immutable immutable staged
  rc_mut_logic 's/if \[ "$stem" != "$FM_ID" \]; then/if false; then # skip id/; s/\[ "$abs" = "$expected" \] || id_bad=1/true # skip id path/' \
    'mutation-check-skip-id: rc_chk id-mismatch-xmd' id-mismatch-xmd id
  rc_mut_logic 's/if ! read_frontmatter "$content_file"; then/if false; then # skip fm/' \
    'mutation-check-skip-malformed: rc_chk malformed-truncated' malformed-truncated malformed
  rc_mut_logic 's/if \[ "$secret_hit" -eq 1 \]; then/if false; then # skip secret/' \
    'mutation-check-skip-secret: rc_chk secret-assignment' secret-assignment secret

  rc_cap_cursor() { # <cu2> <session-id> <user-text> <touch-mode>
    local cu2="$1" sid="$2" text="$3" touch_mode="$4"
    mkdir -p "$cu2/$sid"
    printf '{"role":"user","message":{"content":[{"type":"text","text":%s}]}}\n' \
      "$(printf '%s' "$text" | jq -Rs .)" > "$cu2/$sid/$sid.jsonl"
    case "$touch_mode" in
      live) touch "$cu2/$sid/$sid.jsonl" ;;
      old) touch -t 202501010000 "$cu2/$sid/$sid.jsonl" ;;
      *) touch -t 202610010000 "$cu2/$sid/$sid.jsonl" ;;
    esac
  }

  rc_cap_assert() { # sed assert needle cap_mode
    local sedscript="$1" assert="$2" needle="$3" cap_mode="${4:-since-cursor}"
    mutsh="$(mktemp "${TMPDIR:-/tmp}/memmut.XXXXXX")"
    sed "$sedscript" "$MEMORY_SH" > "$mutsh"; chmod +x "$mutsh"
    mkdir -p "$H2"
    Rc="$T/cap-${assert##*:}"; mkdir -p "$Rc"; git -C "$Rc" init -q
    S1="$(printf '%s' "$Rc" | sed 's/[^A-Za-z0-9]/-/g; s/^-//')"
    CU2="$H2/.cursor/projects/$S1/agent-transcripts"
    case "$cap_mode" in
      subagent) rc_cap_cursor "$CU2" "$id2" "Read and follow the context package at x" idle ;;
      live) rc_cap_cursor "$CU2" c-live-mut hello live ;;
      out-of-range) rc_cap_cursor "$CU2" c-old-mut old old ;;
      unchanged) rc_cap_cursor "$CU2" c-same same idle
        HOME="$H2" bash "$MEMORY_SH" capture --root "$Rc" --since 2026-01-01 --harness cursor >/dev/null 2>&1 ;;
      unreadable) mkdir -p "$CU2/c-bad"
        printf '{{bad json\n' > "$CU2/c-bad/c-bad.jsonl"
        touch -t 202610010000 "$CU2/c-bad/c-bad.jsonl" ;;
    esac
    case "$cap_mode" in
      live) canon_out="$(HOME="$H2" bash "$MEMORY_SH" capture --root "$Rc" --harness cursor 2>&1)"
        out="$(HOME="$H2" bash "$mutsh" capture --root "$Rc" --harness cursor 2>&1)" ;;
      *) canon_out="$(HOME="$H2" bash "$MEMORY_SH" capture --root "$Rc" --since 2026-01-01 --harness cursor 2>&1)"
        out="$(HOME="$H2" bash "$mutsh" capture --root "$Rc" --since 2026-01-01 --harness cursor 2>&1)" ;;
    esac
    rm -f "$mutsh"
    if grep -qF "$needle" <<<"$canon_out" && ! grep -qF "$needle" <<<"$out"; then
      report PASS "$assert"
    else
      report FAIL "$assert" "canon=[$canon_out] mut=[$out]"
    fi
  }

  rc_cap_assert 's/"Read and follow the context package"\*) return 0 ;;//' \
    'mutation-capture-drop-subagent-pattern: capture run1 subagent skip' 'memory: skipped cursor c-sub-mut subagent' subagent
  rc_cap_assert 's/if ! capture_is_idle "$transcript" "$idle"; then/if capture_is_idle "$transcript" "$idle"; then/' \
    'mutation-capture-invert-idle: capture run1 live skip' 'memory: skipped cursor c-live-mut live' live
  rc_cap_assert 's/if \[ -n "$since_ref" \] && capture_since_out_of_range "$transcript" "$since_ref"; then/if false; then # skip since/' \
    'mutation-capture-skip-since: capture out-of-range skip' 'memory: skipped cursor c-old-mut out-of-range' out-of-range
  rc_cap_assert 's/if \[ -n "$latest" \] && \[ "$latest" = "$sha" \]; then/if false; then # skip ledger/' \
    'mutation-capture-skip-ledger: capture second run unchanged' 'memory: skipped cursor c-same unchanged' unchanged
  rc_cap_assert 's/if ! capture_parse_transcript "$harness" "$transcript" "$jq_meta" "$jq_body" "$meta" "$body" "$fu"; then/if false; then # skip parse/' \
    'mutation-capture-skip-unreadable: capture unreadable skip' 'memory: skipped cursor c-bad unreadable' unreadable

  local red_mut=(
    'aws-key:s/REDACT_SED_AWS=.*/REDACT_SED_AWS='"'"'s\/X\/Y\/g'"'"'/:mutation-redact-aws-key'
    'github-token:s/REDACT_SED_GITHUB_A=.*/REDACT_SED_GITHUB_A='"'"'s\/X\/Y\/g'"'"'/:mutation-redact-github-token'
    'api-key:s/REDACT_SED_API=.*/REDACT_SED_API='"'"'s\/X\/Y\/g'"'"'/:mutation-redact-api-key'
    'slack-token:s/REDACT_SED_SLACK=.*/REDACT_SED_SLACK='"'"'s\/X\/Y\/g'"'"'/:mutation-redact-slack-token'
    'jwt:s/REDACT_SED_JWT=.*/REDACT_SED_JWT='"'"'s\/X\/Y\/g'"'"'/:mutation-redact-jwt'
    'azure-key:s/REDACT_SED_AZURE=.*/REDACT_SED_AZURE='"'"'s\/X\/Y\/g'"'"'/:mutation-redact-azure-key'
    'secret:s/redact_secret_assignments "$step" "$tmp"/cp "$step" "$tmp"/:mutation-redact-secret'
    'private-key:s/redact_private_key_body "$in" "$step"/cp "$in" "$step"/:mutation-redact-private-key'
  )
  local item class sedpat assert inp canon mutant
  for item in "${red_mut[@]}"; do
    class="${item%%:*}"; rest="${item#*:}"; sedpat="${rest%%:*}"; assert="${rest##*:}"
    mutsh="$(mktemp "${TMPDIR:-/tmp}/memmut.XXXXXX")"
    sed "$sedpat" "$MEMORY_SH" > "$mutsh"; chmod +x "$mutsh"
    case "$class" in
      aws-key) inp='AKIAABCDEFGHIJKLMNOP' ;;
      github-token) inp='ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' ;;
      api-key) inp='sk-ant-aaaaaaaaaaaaaaaaaaaa' ;;
      slack-token) inp='xoxb-1234567890-abcdefghij' ;;
      jwt) inp='eyJaaaaaaaaaa.eyJbbbbbbbbbb.cccccccccccc' ;;
      azure-key) inp='AccountKey=abc123+/def==' ;;
      secret) inp='password=abcdefgh9' ;;
      private-key) inp=$'-----BEGIN RSA PRIVATE KEY-----\nx\n-----END RSA PRIVATE KEY-----' ;;
    esac
    printf '%s\n' "$inp" > "$B/red-in"
    canon="$(bash "$MEMORY_SH" redact < "$B/red-in" 2>/dev/null)"
    mutant="$(bash "$mutsh" redact < "$B/red-in" 2>/dev/null)"
    if grep -q '\[REDACTED:' <<<"$canon" && ! grep -q '\[REDACTED:' <<<"$mutant"; then
      report PASS "$assert: breaking $class lets secret through"
    else
      report FAIL "$assert" "canon=[$canon] mut=[$mutant]"
    fi
    rm -f "$mutsh"
  done
}
