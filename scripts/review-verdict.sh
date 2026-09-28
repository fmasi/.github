#!/usr/bin/env bash
# Finds the Claude review verdict among a PR's comments. This is the canonical
# copy of the parser. .github/workflows/claude-review.yml inlines the block
# between the BEGIN/END markers byte for byte, because a reusable workflow
# runs in the caller's checkout and cannot read this repo's files.
# scripts/test-review-verdict.sh tests this copy and fails if the two drift.
#
# Usage: review-verdict.sh COMMENTS_JSON SINCE AUTHOR
#   COMMENTS_JSON  a file holding one JSON array of issue comments, as returned
#                  by GET /repos/{owner}/{repo}/issues/{number}/comments (join
#                  paginated output with `jq -s 'add // []'`)
#   SINCE          ISO-8601 UTC time, YYYY-MM-DDTHH:MM:SSZ: the review job's start
#   AUTHOR         the only login whose comments count (claude[bot])
#
# Prints one word:
#   PASS | BLOCK  the newest comment by AUTHOR created at or after SINCE that
#                 contains "REVIEW-VERDICT:" ends with that verdict line
#   NONE          no such comment
#   INVALID       the newest such comment's last non-blank line is not a verdict
# Only that last line counts: a verdict quoted earlier in the text is ignored.
# The line may be wrapped in Markdown emphasis or code marks (*, _, `).
# Exit status: 0 for PASS or BLOCK, 1 for NONE or INVALID, 2 for a usage error.

# BEGIN review_verdict
review_verdict() {
  # $1 = comments JSON file, $2 = SINCE (ISO-8601 UTC), $3 = author login
  jq -r --arg since "$2" --arg author "$3" '
    [ .[]
      | select(.user.login == $author
               and .created_at >= $since
               and ((.body // "") | contains("REVIEW-VERDICT:"))) ]
    | sort_by(.created_at, .id)
    | last
    | if . == null then "NONE"
      else
        ( .body | gsub("\r"; "") | split("\n")
          | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))
          | last // "" ) as $line
        | ($line | capture("^[*_`]*REVIEW-VERDICT: (?<v>PASS|BLOCK)[*_`]*$") | .v)
          // "INVALID"
      end
  ' "$1"
}
# END review_verdict

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  if [[ $# -ne 3 ]]; then
    echo "usage: $0 COMMENTS_JSON SINCE AUTHOR" >&2
    exit 2
  fi
  verdict=$(review_verdict "$@")
  echo "$verdict"
  case "$verdict" in
    PASS | BLOCK) exit 0 ;;
    *) exit 1 ;;
  esac
fi
