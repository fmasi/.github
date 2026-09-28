# fmasi/.github: instructions for coding agents

Every coding agent reads this file: Claude Code (through `@AGENTS.md` in CLAUDE.md), Codex, Copilot,
Cursor and others. The owner doesn't read code. The checks below are the safety net, so follow
them exactly.

This repo holds the **shared reusable workflows every fmasi repo calls at `@main`**:
`claude-review.yml` (the one required Claude review and its `review / review-gate` merge gate),
`claude-mention.yml` (`@claude`, owner-gated), `just-ci.yml` (one job: gitleaks + `just ci`) and
`traffic-snapshot.yml`. **A change here changes CI in every repo the moment it merges.**

## How work lands here

1. Branch from `main`. Never commit on `main`.
2. The pre-commit hook (lefthook) runs gitleaks and actionlint. Once per clone: `lefthook install`.
3. `just ci` must pass before every push: actionlint, zizmor (high severity) and the verdict-parser
   tests. The pre-push hook runs it.
4. Open a PR (`gh pr create --fill`). This repo's own CI (`ci / ci`) is the required check.
   The Claude review does not apply here: its action skips PRs that change workflow files, and
   almost every PR here does.
5. Before merging a change to a reusable workflow, prove it on a caller repo. Point one caller's
   `uses:` at your branch (`@<branch>`) in a draft PR there, run it, then revert that pointer.
6. The rules bind everyone, the owner included. Nobody bypasses them.

## Commands

`just --list` shows every recipe. The ones that matter:
- `just ci`: what CI runs (`lint` + `test`).
- `just lint`: actionlint + zizmor.
- `just test`: shellcheck + the review-verdict parser tests.

## Repo rules

- Keep every third-party action pinned by full commit SHA, with a `# vX.Y.Z` comment.
- Changing an input, a secret, a job id or permissions breaks callers or their required-check
  names (`review / review-gate`, `review / claude-review`, `ci / ci`). Such a change needs the
  caller updates first, then this merge, then the rulesets, in that order. Document it in the PR.
- Only comments by `claude[bot]` may count as a review verdict. Never weaken that.
- New or changed shell logic comes with a test in `scripts/`.

## Never

- Never merge with `gh pr merge --admin`, and never try any other way around the ruleset.
- Never use `--no-verify` (on `git commit` or `git push`) to skip the hooks or `just ci`.
- Never add the `claude-reviewed` label yourself anywhere. Only the review workflow and the owner do.
- Never push to `main`. Every change goes through a PR.
- Never commit secrets or tokens. This repo is public.
