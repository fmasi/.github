set shell := ["bash", "-euo", "pipefail", "-c"]

default: ci

# EXACTLY what CI runs: just-ci.yml's `workflow-lint` steps (= `lint`), then `just test`.
ci: lint test

# Needs actionlint and zizmor (brew install actionlint zizmor). CI pins
# actionlint 1.7.12 and zizmor 1.30.1, and gives zizmor a token for its online
# audits; locally it borrows the gh CLI's token when GH_TOKEN is unset.
lint:
    actionlint
    if [ -z "${GH_TOKEN:-}" ] && t=$(gh auth token 2>/dev/null); then export GH_TOKEN="$t"; fi; zizmor --min-severity high .github/workflows

test:
    shellcheck scripts/*.sh
    bash scripts/test-review-verdict.sh

# Workflow parity check: lists every job act can see.
act:
    act -l
