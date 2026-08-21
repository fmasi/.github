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

This needs **two** tokens, not one — GitHub's traffic endpoints require
**Administration: Read** on the repo being read, a permission `GITHUB_TOKEN`
(the automatic Actions token) can never be granted, at any `permissions:`
setting, by design. So one token reads traffic off the source repo, and a
separate, narrower token writes the snapshot into `traffic-data`. Keeping
them apart matters: "Administration" is a broad-sounding permission (repo
settings, webhooks, deploy keys, branch protection visibility, not just
traffic counts), so it shouldn't be bundled onto a token that also has write
access to another repo.

1. **One-time, reusable across repos**: create a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new)
   named e.g. `traffic-read`, scoped to whichever repos you want traffic
   snapshots for (select them explicitly, or "All repositories" if you'd
   rather it auto-cover future ones — that trades scope precision for less
   maintenance), with **Administration: Read** and nothing else. This one
   token's value can be reused as the same secret in every repo it covers.

2. **One-time**: create a second fine-grained PAT (already done as
   `traffic-snapshot-writer` if you're reading this after the first setup)
   scoped to the single repository `fmasi/traffic-data`, with **Contents:
   Read and write** permission and nothing else.

   Both PATs require an expiry (max 1 year) — set a calendar reminder to
   rotate each, since a silently expired token means snapshots quietly stop
   with no user-visible failure unless you check Actions runs.

3. Add both as secrets **in the repo you're adding this to** (not here —
   personal GitHub accounts don't support account-wide Actions secrets the
   way Organizations do, so this is a per-repo step):

   ```
   gh secret set TRAFFIC_READ_TOKEN --repo fmasi/<repo>
   gh secret set TRAFFIC_DATA_TOKEN --repo fmasi/<repo>
   ```

   Run them bare like that (no `--body`/value argument) so each prompts
   interactively — the token value never touches shell history or a
   terminal transcript.

4. Add this caller workflow at `.github/workflows/traffic-snapshot.yml` in
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

5. Trigger it once by hand (Actions tab → Traffic Snapshot → Run workflow)
   to confirm both tokens work before waiting for the schedule.

Referenced with `@main` rather than a pinned tag/SHA deliberately: these are
your own repos, not a third-party dependency, so the propagation benefit
("every caller gets a fix the moment it lands") outweighs the pin-for-audit-
trail argument that applies to external actions.
