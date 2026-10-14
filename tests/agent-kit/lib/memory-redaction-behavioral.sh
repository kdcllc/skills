# Sourced inside run_behavioral_suite (bash/pwsh/parity). Uses caller ok/ko/run/expect_rc and twin vars.

run_release_c_redaction_behavioral() {
  local RR="" GH="" PAT="" SK="" JWT="" f="" id="" sha="" leaks=0 exp_redact=
  mktemp_root RR

  twins_redact_diverge_p() { # <infile> <ps1-path> → exit 0 when bash vs pwsh redact stdout differ
    local in="$1" ps1="$2"
    bash "$MEMORY_SH" redact < "$in" >"$B/twin.a" 2>/dev/null
    pwsh -NoProfile -NonInteractive -File "$ps1" redact < "$in" >"$B/twin.b" 2>/dev/null
    ! cmp -s "$B/twin.a" "$B/twin.b"
  }

  release_c_redact() { # <infile> [optional MEMORY_PS1 override for pwsh leg]
    local in="$1" ps1="${2:-$MEMORY_PS1}" rc_b=0
    if [[ "${M_PARITY:-0}" -eq 1 ]]; then
      bash "$MEMORY_SH" redact < "$in" >"$B/out_a" 2>"$B/err_a"; RC=$?
      pwsh -NoProfile -NonInteractive -File "$ps1" redact < "$in" >"$B/out_b" 2>"$B/err_b"; rc_b=$?
      parity_step "$RC" "$rc_b" "redact $(basename "$in")"
      OUT="$(cat "$B/out_a")"; ERR="$(cat "$B/err_a")"
    else
      OUT="$("${RUN[@]}" redact < "$in" 2>"$B/err_a")"; RC=$?
      ERR="$(cat "$B/err_a")"
    fi
  }

  rc_near_miss() { # <label> <input-bytes>
    local nm="$1" exp="$2"
    printf '%s' "$exp" > "$B/nm.in"
    cp "$B/nm.in" "$B/nm.exp"
    release_c_redact "$B/nm.in"
    printf '%s' "$OUT" > "$B/nm.out"
    cmp -s "$B/nm.exp" "$B/nm.out" && [[ -z "$ERR" ]] && ok "near-miss $nm unchanged" \
      || ko "near-miss $nm" "out=[$OUT] err=[$ERR]"
  }

  echo "  == rc redact stdin (CRLF, no-LF, azure nbsp)"
  printf 'a\r\npassword=abcdefgh9\r\nb\r\n' > "$B/rc.crlf"
  release_c_redact "$B/rc.crlf"
  grep -q '\[REDACTED:secret\]' <<<"$OUT" && ok "redact CRLF secret" || ko "redact CRLF"
  printf 'password=abcdefgh9' > "$B/rc.nolf"
  release_c_redact "$B/rc.nolf"
  grep -q '\[REDACTED:secret\]' <<<"$OUT" && ok "redact no final LF" || ko "redact no-LF"
  printf 'AccountKey=\302\240abcdef==\nSharedAccessKey=x\302\205y;z\n' > "$B/rc.nbsp"
  release_c_redact "$B/rc.nbsp"
  grep -q '\[REDACTED:azure-key\]' <<<"$OUT" && ok "redact azure 0xA0/0x85" || ko "redact azure nbsp"

  echo "  == rc near-miss per class"
  rc_near_miss secret-7char 'password=abcdefg'
  rc_near_miss secret-placeholder 'password=<placeholder>'
  rc_near_miss secret-dollar 'token=$TOKEN'
  rc_near_miss secret-backtick 'token: `{{X}}`'
  rc_near_miss aws-key-15 'key AKIAABCDEFGHIJKLMNO here'
  rc_near_miss github-35 "tok ghp_$(printf 'a%.0s' $(seq 1 35)) end"
  rc_near_miss api-sk-19 'api sk-aaaaaaaaaaaaaaaaaaa'
  rc_near_miss slack-short 'slack xoxb-123'
  rc_near_miss jwt-seg9 'eyJ1234567.eyJ1234567.123456789'
  rc_near_miss azure-idempotent 'AccountKey=[REDACTED:azure-key];next=1'
  rc_near_miss pk-no-private '-----BEGIN CERTIFICATE-----\ndata\n-----END CERTIFICATE-----'

  echo "  == rc private-key variants (redact)"
  printf 'pre\n-----BEGIN RSA PRIVATE KEY-----\nMII\n-----END RSA PRIVATE KEY-----\npost\n' > "$B/rc.pk1"
  release_c_redact "$B/rc.pk1"; grep -q '\[REDACTED:private-key\]' <<<"$OUT" && ok "pk terminated block" || ko "pk terminated" "[$OUT]"
  printf 'a\n-----BEGIN OPENSSH PRIVATE KEY-----\nzz\n' > "$B/rc.pk2"
  release_c_redact "$B/rc.pk2"; grep -q '\[REDACTED:private-key\]' <<<"$OUT" && ok "pk unterminated" || ko "pk unterminated"
  printf 'pre\n-----BEGIN PRIVATE KEY-----abc-----END PRIVATE KEY-----\npost\n' > "$B/rc.pk3"
  release_c_redact "$B/rc.pk3"; grep -q '\[REDACTED:private-key\]' <<<"$OUT" && ok "pk same-line" || ko "pk same-line"
  printf 'a\n-----BEGIN RSA PRIVATE KEY-----\nx\n-----BEGIN EC PRIVATE KEY-----y-----END EC PRIVATE KEY-----\nkeep\n' > "$B/rc.pk4"
  release_c_redact "$B/rc.pk4"; grep -q '\[REDACTED:private-key\]' <<<"$OUT" && grep -q '^keep$' <<<"$OUT" && ok "pk in-block END precedence" || ko "pk in-block"

  echo "  == rc idempotency (redact twice)"
  printf 'password=hunter2xyz\nAccountKey=abc123+/def==\n' > "$B/rc.idem"
  release_c_redact "$B/rc.idem"; printf '%s' "$OUT" > "$B/id1"
  release_c_redact "$B/id1"
  printf '%s' "$OUT" > "$B/id2"
  cmp -s "$B/id1" "$B/id2" && ok "redact idempotent stdout" || ko "idempotent stdout"
  [[ -z "$ERR" ]] && ok "redact idempotent stderr empty" || ko "idempotent stderr" "[$ERR]"

  echo "  == rc all 8 classes via add + tags/harness hygiene"
  GH="ghp_$(printf 'a%.0s' $(seq 1 36))"
  PAT="github_pat_$(printf 'B%.0s' $(seq 1 22))"
  SK="sk-ant-$(printf 'c%.0s' $(seq 1 20))"
  JWT="eyJ$(printf 'd%.0s' $(seq 1 10)).eyJ$(printf 'e%.0s' $(seq 1 10)).$(printf 'f%.0s' $(seq 1 10))"
  cat > "$B/rc.all" <<EOF
intro
Password: "s3cretValue9"
key AKIAABCDEFGHIJKLMNOP here
tok $GH and $PAT
api ($SK)
slack xoxb-1234567890-abc
jwt $JWT
conn DefaultEndpointsProtocol=https;AccountKey=abc123+/def==;EndpointSuffix=x
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA
-----END RSA PRIVATE KEY-----
outro
EOF
  run 20261013T100000Z add --kind fact --title 'all classes token=abcdefgh12' --body "$B/rc.all" \
    --tags 'a1,b2,c3,d4,e5,f6,g7' --harness claude --root "$RR"
  expect_rc 0 "all-classes add rc"
  [[ "$OUT" == memory:\ added* ]] && ok "add stdout format unchanged" || ko "add stdout" "[$OUT]"
  f="$(find "$RR/_memory/records" -name '*.md' | head -1)"
  sha="$(grep '^sha256:' "$f" | awk '{print $2}')"
  leaks=0
  for s in hunter2 s3cretValue9 AKIAABCDEFGHIJKLMNOP "$GH" "$PAT" "$SK" xoxb-1234567890 "$JWT" abc123 MIIEowIBAAKCAQEA abcdefgh12; do
    grep -qF -- "$s" "$f" && leaks=1
  done
  [[ "$leaks" -eq 0 ]] && ok "all-classes no leaks in record" || ko "all-classes leaks"
  body_sha="$(awk 'c>=2{print} /^---$/{c++}' "$f" | sha256sum | cut -c1-64)"
  [[ "$body_sha" == "$sha" ]] && ok "sha256 over redacted body" || ko "sha over redacted" "fm=$sha body=$body_sha"
  grep -qF "api ([REDACTED:api-key])" "$f" && ok "boundary paren kept around api-key" || ko "api-key boundary" "$(grep api "$f")"
  exp_redact='memory: redacted 10 secret(s): private-key,secret,aws-key,github-token,api-key,slack-token,jwt,azure-key'
  grep -qxF "$exp_redact" <<<"$ERR" && ok "exact redaction stderr line once" \
    || ko "exact redact stderr" "[$ERR]"
  [[ "$(grep -c '^memory: redacted ' <<<"$ERR")" -eq 1 ]] && ok "redact stderr line count 1" || ko "redact stderr count"
  red_ln="$(grep -n 'memory: redacted' <<<"$ERR" | head -1 | cut -d: -f1)"
  trunc_ln="$(grep -n 'memory: tags truncated to 6' <<<"$ERR" | head -1 | cut -d: -f1)"
  [[ -n "$red_ln" && -n "$trunc_ln" && "$red_ln" -lt "$trunc_ln" ]] && ok "redact line before tags-truncated" || ko "stderr order" "r=$red_ln t=$trunc_ln"

  printf 'tag body\n' > "$B/rc.tags1"
  run 20261013T100001Z add --kind fact --title 'tags mix' --body "$B/rc.tags1" --tags 'A1 b2,B2' --root "$RR"
  grep -q '^tags: \[a1, b2\]$' "$RR/_memory/records/2026/10/"*.md 2>/dev/null && ok "tags A1 b2,B2 normalize" \
    || ko "tags A1 b2,B2" "$(grep '^tags' "$RR/_memory/records/2026/10/"*.md | tail -1)"
  printf 'tag2 body\n' > "$B/rc.tags2"
  run 20261013T100002Z add --kind fact --title 'tags sep' --body "$B/rc.tags2" --tags $'a1\tb2\rc3' --root "$RR"
  grep -q '^tags: \[a1, b2, c3\]$' "$RR/_memory/records/2026/10/"*.md 2>/dev/null && ok "tags tab/cr split" \
    || ko "tags tab cr" "$(grep '^tags' "$RR/_memory/records/2026/10/"*.md | tail -1)"

  printf 'tag body\n' > "$B/rc.t7"
  run 20261013T100003Z add --kind fact --title 'tags seven' --body "$B/rc.t7" --tags 'a1,b2,c3,d4,e5,f6,g7' --root "$RR"
  grep -q 'memory: tags truncated to 6' <<<"$ERR" && ok "7 tags truncated stderr" || ko "7 tags stderr"
  run 20261013T100004Z add --kind fact --title cc --body "$B/rc.t7" --harness claude-code --root "$RR"
  expect_rc 2 "harness claude-code exit 2"

  echo "  == rc positive one-liner per class (redact twin)"
  printf 'password=abcdefgh9\n' > "$B/rc.sec"; release_c_redact "$B/rc.sec"; grep -q '\[REDACTED:secret\]' <<<"$OUT" && ok "class secret" || ko "class secret"
  printf 'AKIAABCDEFGHIJKLMNOP\n' > "$B/rc.aws"; release_c_redact "$B/rc.aws"; grep -q '\[REDACTED:aws-key\]' <<<"$OUT" && ok "class aws-key" || ko "class aws"
  printf 'tok %s\n' "$GH" > "$B/rc.gh"; release_c_redact "$B/rc.gh"; grep -q '\[REDACTED:github-token\]' <<<"$OUT" && ok "class github-token" || ko "class gh"
  printf '(%s)\n' "$SK" > "$B/rc.api"; release_c_redact "$B/rc.api"; grep -q '\[REDACTED:api-key\]' <<<"$OUT" && ok "class api-key" || ko "class api"
  printf 'xoxb-1234567890-abcdefghij\n' > "$B/rc.sl"; release_c_redact "$B/rc.sl"; grep -q '\[REDACTED:slack-token\]' <<<"$OUT" && ok "class slack-token" || ko "class slack"
  printf '%s\n' "$JWT" > "$B/rc.jwt"; release_c_redact "$B/rc.jwt"; grep -q '\[REDACTED:jwt\]' <<<"$OUT" && ok "class jwt" || ko "class jwt"
  printf 'AccountKey=abc123+/def==\n' > "$B/rc.az"; release_c_redact "$B/rc.az"; grep -q '\[REDACTED:azure-key\]' <<<"$OUT" && ok "class azure-key" || ko "class azure"
  printf '%s\n' '-----BEGIN RSA PRIVATE KEY-----' 'x' '-----END RSA PRIVATE KEY-----' > "$B/rc.pk"
  release_c_redact "$B/rc.pk"; grep -q '\[REDACTED:private-key\]' <<<"$OUT" && ok "class private-key" || ko "class pk"

  if [[ "$label" == "__parity__" ]] && command -v pwsh >/dev/null 2>&1; then
    local mut_ps1=""
    printf 'password=abcdefgh9\n' > "$B/parity.proof.in"
    if twins_redact_diverge_p "$B/parity.proof.in" "$MEMORY_PS1"; then
      ko "parity redact negative control" "canonical twins must not diverge"
    else
      echo "PASS: parity redact negative control: canonical twins match (no divergence)"
      ok "parity redact negative control: canonical twins match (no divergence)"
    fi
    mut_ps1="$(mktemp "${TMPDIR:-/tmp}/memps1mut.XXXXXX")"
    sed 's/\[REDACTED:secret\]/[REDACTED:SECRET]/' "$MEMORY_PS1" > "$mut_ps1"
    if twins_redact_diverge_p "$B/parity.proof.in" "$mut_ps1"; then
      echo "PASS: parity redact compares stdout bytes (mutant ps1 diverges)"
      ok "parity redact compares stdout bytes (mutant ps1 diverges)"
    else
      ko "parity redact proof" "mutant did not diverge"
    fi
    rm -f "$mut_ps1"
  fi

  if [[ "$label" != "__parity__" ]]; then
    rm -rf "$RR"
  fi
}
