# The report

One rolling Artifact page per branch. Each review adds an iteration to it, at the same
link. Teammates tick findings resolved on the page; a ticked finding folds to its title
for everyone. `scripts/build_report.py` builds the page from the verifier's
`verified.json`, and also derives the tags and the verdict, so the orchestrator copies
files and never judges a finding.

## Tags and verdict

Derived by the script, never by hand:

| Tag | When |
|---|---|
| `disputed` | the entry has a `Disputed:` line |
| `needs decision` | every `CONTRACT:`; a `SIMPLIFY:` whose `Costs:` is not "nothing" |
| `confirm first` | the verifier said PLAUSIBLE |
| `mechanical` | everything else: the fix is stated, apply it |

Verdict: any CRITICAL → blocked; any HIGH → needs changes; MEDIUM only → ship with nits;
none → ship. Refuted, pre-existing and question entries carry no tag. Whoever fixes the
findings does not act on them unless the user says so.

## Before the verifier: find the previous iteration

```bash
source <run>/env.sh
```

- `PREV_URL` set, or a page titled `<SLUG> review` in the Artifact list: read it with the
  Artifact tool (`action: "read"`). The result names the saved file.
- With a previous page, read its ticks: `ArtifactData` `list` on collection `resolved`.
  The ids there are the team's "resolved" ticks. Ask the user for any findings they waive.
- Then:

```bash
python3 -I <skill dir>/scripts/build_report.py prev --env <run>/env.sh [--prev <saved file>]
```

It writes `<run>/prev.json` (the last iteration's findings) and prints the next iteration
number `N`. Both go into the verify prompt, with the waived ids and the ticked ids.

## After the verifier: build and publish

```bash
python3 -I <skill dir>/scripts/build_report.py build --env <run>/env.sh [--prev <saved file>] \
  --roster "<agents run>" --skipped "<agents skipped and why>" --models "<who ran on what>" \
  --verify-cmd "<the test command the repo's CLAUDE.md names>" [--single-context]
```

It writes `<run>/report.html`. Publish it with the Artifact tool:

- **First iteration:** `file_path: <run>/report.html`, `icon: "checklist"`,
  `capabilities: {db: {}, user: {}}`, and a one-sentence `description` naming the repo and
  branch. Then save the URL so the next review finds it:
  `mkdir -p "$INDEX_DIR" && echo "<url>" > "$INDEX_DIR/$SLUG.url"`.
- **Later iterations:** the same call with `url: <PREV_URL>`, and no `icon` and no
  `capabilities`, so the page keeps both. The ticks live in the page's store and survive
  the republish.

`INDEX_DIR` is inside the repository's shared git directory, so every worktree of the
repository finds the same report, and nothing appears in `git status`.

The `resolved` collection is the only shared state: one document per ticked finding id,
`{resolved: true, at}`. A finding the verifier marks `reopened` (ticked, yet still present)
shows unfolded until someone ticks it again.

## No Artifact tool

When this session has no Artifact tool, add `--md`. The script writes
`$INDEX_DIR/<SLUG>-r<N>.md` with the same content and the data embedded in a comment, so
the next review can pass that file as `--prev`. There are no ticks in this mode; ask the
user which findings are resolved or waived. Say in the relay that the report is a file,
and give its path.

## Relay to the user

In chat, in this order: the verdict line; the findings, in full; the open questions; the
refuted entries with their reasons; nits and pre-existing items as counts; the report
link. No praise, and no summary of what the change does: the author already knows.
