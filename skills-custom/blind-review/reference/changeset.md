# Resolving the changeset and taking the snapshot

`scripts/snapshot.sh` does all of it in one call and prints only the shape. Never print
the snapshot, the claims or any changed file yourself.

## Targets

| Target | How the user says it | Base | Code the agents read |
|---|---|---|---|
| Current branch (default) | nothing, "my branch", "before I push" | the branch's open PR base if one exists, else the default branch | the working tree: committed, uncommitted and untracked |
| Stacked branch | `--base <branch>` | that branch | same |
| PR | a number, `owner/repo#N`, or a URL | the PR's base, or `--base` | a detached worktree at the PR head, inside the run directory |
| Batch | several of the above | each its own | each its own run |

Run from a checkout of the repository the change belongs to. A PR in another repository
needs a checkout of that repository; the script refuses otherwise.

## Run it

```bash
<skill dir>/scripts/snapshot.sh <scratch root> [--base <branch>] [<pr>]
```

`<scratch root>` is the scratchpad directory your system prompt names, or
`${TMPDIR:-/tmp}` when it names none. The script:

- fetches `origin`, resolves the base and the merge-base;
- creates a new run directory for this review, so no two runs share a file;
- writes `snapshot.diff`, `paths.txt`, `claims.md`, `pr.json` (when a PR exists) and
  `env.sh`;
- prints the run directory, the agents' repo root, the target line, the shape and any
  previous report URL.

It stops with a message on the default branch with no PR, on a detached HEAD, or on an
empty base.

Every later shell step starts with `source <run>/env.sh`. Shell variables do not survive
between tool calls; `env.sh` holds `RUN`, `AGENT_ROOT`, `SNAP`, `CLAIMS`, `SLUG`,
`HEAD_SHA`, `BASE`, `BASE_REF`, `TREE`, `CHANGED`, `INDEX_DIR` and `PREV_URL`.

## The shape — the only thing you look at

The printed block: changed lines (from `git diff --numstat`), changed paths, test paths,
security-sensitive paths, issues found, previous report, and the path list. The roster
rule in `SKILL.md` reads these and nothing else.

If changed lines is 0, stop and say there is nothing to review.

## PR worktree

In PR mode the agents' repo root is `<run>/worktree`, a detached worktree at the PR head.
Remove it after the report with `git worktree remove --force <run>/worktree`, unless the
user wants it kept for fixing.

**A stacked PR whose base is still the default branch** carries its parent's work in the
diff. The intent agent reports "the diff holds more than this change"; if the user
confirms a stack, run again with the parent as `--base`.

## Claims for the intent agent

`claims.md` holds, labelled as claims: the PR description, every linked issue, each
issue's parent and grandparent, and the commit messages. Issues come from the PR's
closing references, then `Fixes #N`-style commit trailers, then a number in the branch
name (marked as a guess). Only the intent agent receives this file.

If no issue was found, ask the user what the change is for and append their answer to
`claims.md` under `## Stated purpose (the author's claim)`.

## Batch — several changesets

Run the script once per target. Run Steps 2–4 of `SKILL.md` per run. Then one more
**intent** dispatch gets every snapshot and every per-run `verified.json`, in deployment
order (`doctrine-lakefs.md`), and reconciles the contract surfaces: producer against
consumer for every API shape, schema, config key, flag, auth rule and version assumption.
A contract change with no counterpart is a finding. Its output becomes the `batch` part of
the lead target's report (`report.md`).

## Re-review

`PREV_URL` in `env.sh` is the previous report for this branch. Branch mode and PR mode
use the same branch-named slug, so a local review and a later PR review form one chain.
When `PREV_URL` is empty, check the Artifact list for a page titled `<SLUG> review` before
deciding this is the first iteration.
