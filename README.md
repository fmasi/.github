# .github

Account-wide defaults and shared reusable GitHub Actions workflows for
`fmasi` repos. "Maintain once, use many" — fix or improve a workflow here,
every repo that calls it picks up the change on its next run.

## Traffic snapshot

GitHub's traffic API (clones, views, referrers, popular paths) only retains a
**rolling 14-day window** — on every plan, including Enterprise Cloud. No tier
extends it, and no historical data survives once it ages out, for anyone,
ever. `traffic-snapshot.yml` closes that gap: run daily, it fetches a repo's
current window and appends it to a durable JSON file in the private
[`fmasi/traffic-data`](https://github.com/fmasi/traffic-data) repo, one file
per source repo (`<repo>.json`).

### Adding it to a new repo

1. **One-time**: create a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new)
   scoped to the single repository `fmasi/traffic-data`, with **Contents:
   Read and write** permission and nothing else. Fine-grained PATs require an
   expiry (max 1 year) — set a calendar reminder to rotate it, since a
   silently expired token means snapshots quietly stop with no user-visible
   failure unless you check Actions runs.

2. Add it as a secret **in the repo you're adding this to** (not here —
   personal GitHub accounts don't support account-wide Actions secrets the
   way Organizations do, so this is a per-repo step):

   ```
   gh secret set TRAFFIC_DATA_TOKEN --repo fmasi/<repo>
   ```

   Run it bare like that (no `--body`/value argument) so it prompts
   interactively — the token value never touches shell history or a
   terminal transcript.

3. Add this caller workflow at `.github/workflows/traffic-snapshot.yml` in
   the target repo:

   ```yaml
   name: Traffic Snapshot

   "on":
     schedule:
       - cron: "17 4 * * *"
     workflow_dispatch: {}

   permissions:
     contents: read

   jobs:
     snapshot:
       uses: fmasi/.github/.github/workflows/traffic-snapshot.yml@main
       secrets: inherit
   ```

4. Trigger it once by hand (Actions tab → Traffic Snapshot → Run workflow)
   to confirm the token works before waiting for the schedule.

Referenced with `@main` rather than a pinned tag/SHA deliberately: these are
your own repos, not a third-party dependency, so the propagation benefit
("every caller gets a fix the moment it lands") outweighs the pin-for-audit-
trail argument that applies to external actions.
