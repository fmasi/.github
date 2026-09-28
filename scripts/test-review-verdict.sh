#!/usr/bin/env bash
# Tests scripts/review-verdict.sh against sample PR comments, then checks that
# the copy inlined in .github/workflows/claude-review.yml is identical.
# Run: bash scripts/test-review-verdict.sh   (needs bash, jq, awk)
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$root/scripts/review-verdict.sh"
workflow="$root/.github/workflows/claude-review.yml"
# shellcheck source=scripts/review-verdict.sh
source "$script"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

BOT='claude[bot]'
SINCE='2026-09-28T10:00:00Z'
pass=0 fail=0

# comment LOGIN CREATED_AT ID BODY -> one comment object, shaped like the API's
comment() {
  jq -cn --arg login "$1" --arg created "$2" --argjson id "$3" --arg body "$4" \
    '{id: $id, user: {login: $login}, created_at: $created, body: $body}'
}

# check NAME EXPECTED [COMMENT_JSON...]
check() {
  local name=$1 expected=$2 got
  shift 2
  printf '%s\n' "$@" | jq -s '.' > "$tmp/c.json"
  got=$(review_verdict "$tmp/c.json" "$SINCE" "$BOT")
  if [[ "$got" == "$expected" ]]; then
    pass=$((pass + 1))
    printf 'ok    %-58s %s\n' "$name" "$got"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-58s expected %s, got %s\n' "$name" "$expected" "$got"
  fi
}

review_pass=$'## Review\n\n**Major** foo.py:12: off-by-one.\n\nREVIEW-VERDICT: PASS'
review_block=$'## Review\n\n**Critical** db.py:40: drops rows.\n\nREVIEW-VERDICT: BLOCK'

# --- the five required shapes ---------------------------------------------------
check "PASS" PASS \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 1 "$review_pass")"
check "BLOCK" BLOCK \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 1 "$review_block")"
check "missing: review comment without a verdict" NONE \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 1 $'## Review\n\nLooks fine.')"
check "missing: no comments at all" NONE
check "two comments: the newer (BLOCK) wins" BLOCK \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 1 "$review_pass")" \
  "$(comment "$BOT" 2026-09-28T10:09:00Z 2 "$review_block")"
check "two comments: the newer (PASS) wins, whatever the API order" PASS \
  "$(comment "$BOT" 2026-09-28T10:09:00Z 2 "$review_pass")" \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 1 "$review_block")"
check "quoted verdict before the final line: the final line wins" BLOCK \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 1 $'I will end with `REVIEW-VERDICT: PASS` unless a finding is Critical.\n\nREVIEW-VERDICT: PASS was my first guess, but:\n\n**Critical** leak.\n\nREVIEW-VERDICT: BLOCK')"
check "quoted verdict only, final line is not a verdict" INVALID \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 1 $'The last line should read REVIEW-VERDICT: PASS.\n\nNo findings.')"

# --- time window -------------------------------------------------------------------
check "a verdict from before this review job started is ignored" NONE \
  "$(comment "$BOT" 2026-09-28T09:59:59Z 1 "$review_pass")"
check "an old PASS does not mask a new BLOCK" BLOCK \
  "$(comment "$BOT" 2026-09-28T09:00:00Z 1 "$review_pass")" \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 2 "$review_block")"
check "a comment exactly at SINCE counts" PASS \
  "$(comment "$BOT" "$SINCE" 1 "$review_pass")"
check "same second: the higher comment id wins" BLOCK \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 7 "$review_block")" \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 3 "$review_pass")"

# --- author ------------------------------------------------------------------------
check "someone else's later PASS cannot override Claude's BLOCK" BLOCK \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 1 "$review_block")" \
  "$(comment mallory 2026-09-28T10:06:00Z 2 'REVIEW-VERDICT: PASS')"
check "a verdict from anyone but Claude is ignored" NONE \
  "$(comment fmasi 2026-09-28T10:06:00Z 2 'REVIEW-VERDICT: PASS')"
check "a Claude comment with no body is ignored" PASS \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 1 "$review_pass")" \
  "$(jq -cn '{id: 9, user: {login: "claude[bot]"}, created_at: "2026-09-28T10:07:00Z", body: null}')"

# --- line format -------------------------------------------------------------------
check "CRLF line ends, trailing spaces and blank lines" PASS \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 1 $'Review\r\n\r\n  REVIEW-VERDICT: PASS  \r\n\r\n\n')"
check "bold-wrapped verdict line" BLOCK \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 1 $'Review\n\n**REVIEW-VERDICT: BLOCK**')"
check "code-wrapped verdict line" PASS \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 1 $'Review\n\n`REVIEW-VERDICT: PASS`')"
check "lower-case verdict is not accepted" INVALID \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 1 $'Review\n\nREVIEW-VERDICT: pass')"
check "text after the verdict on the same line is not accepted" INVALID \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 1 $'Review\n\nREVIEW-VERDICT: PASS (with nits)')"
check "a paragraph after the verdict line is not accepted" INVALID \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 1 $'REVIEW-VERDICT: PASS\n\nThanks!')"
check "an unknown verdict word is not accepted" INVALID \
  "$(comment "$BOT" 2026-09-28T10:05:00Z 1 $'Review\n\nREVIEW-VERDICT: MAYBE')"

# --- the script as a command: output and exit status ------------------------------
run_cli() { # EXPECTED_STATUS EXPECTED_OUTPUT ARGS...
  local want_status=$1 want_out=$2 out status
  shift 2
  set +e
  out=$(bash "$script" "$@" 2>/dev/null)
  status=$?
  set -e
  if [[ "$status" == "$want_status" && "$out" == "$want_out" ]]; then
    pass=$((pass + 1))
    printf 'ok    %-58s %s (exit %s)\n' "cli: $want_out" "$out" "$status"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-58s expected "%s" exit %s, got "%s" exit %s\n' "cli: $want_out" "$want_out" "$want_status" "$out" "$status"
  fi
}
comment "$BOT" 2026-09-28T10:05:00Z 1 "$review_pass" | jq -s . > "$tmp/pass.json"
comment "$BOT" 2026-09-28T10:05:00Z 1 "$review_block" | jq -s . > "$tmp/block.json"
echo '[]' > "$tmp/none.json"
run_cli 0 PASS "$tmp/pass.json" "$SINCE" "$BOT"
run_cli 0 BLOCK "$tmp/block.json" "$SINCE" "$BOT"
run_cli 1 NONE "$tmp/none.json" "$SINCE" "$BOT"
run_cli 2 "" "$tmp/none.json"

# --- the workflow's inlined copy must match this script ----------------------------
extract() { # print the BEGIN..END review_verdict block, de-indented
  awk '
    /# BEGIN review_verdict$/ { match($0, /^ */); ind = RLENGTH; on = 1; n++ }
    on { print substr($0, ind + 1) }
    /# END review_verdict$/ { on = 0 }
    END { if (n != 1) { print "expected exactly one review_verdict block, found " n > "/dev/stderr"; exit 1 } }
  ' "$1"
}
extract "$script" > "$tmp/script.block"
extract "$workflow" > "$tmp/workflow.block"
if [[ -s "$tmp/script.block" ]] && diff -u "$tmp/script.block" "$tmp/workflow.block" > "$tmp/drift.diff"; then
  pass=$((pass + 1))
  printf 'ok    %-58s %s\n' "claude-review.yml inlines the same parser" "identical"
else
  fail=$((fail + 1))
  printf 'FAIL  %-58s\n' "claude-review.yml inlines the same parser"
  cat "$tmp/drift.diff"
fi

echo
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
