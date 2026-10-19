---
name: challenge-me
description: Use when the user wants alternatives to a PR, branch, plan or design - "challenge me", "challenge this PR", "is there a better approach", "what else could we have done", or before committing to a design direction.
---

# Challenge Me

Present 2-3 high-level alternatives to the approach a PR or design takes, side by side with it.

## Core Principle

Whoever has seen the solution proposes variations of it. So the agent that invents alternatives never sees the PR. It gets only the problem, and sees the current approach only after its own approaches are written down.

Not for finding bugs (`self-review`) or stress-testing one chosen approach (`grill-me`).

## Step 1 — Extract the Problem

Dispatch a fresh `general-purpose` agent (model `opus`, never `fork`):

```
Read <PR number | branch vs base | design doc path> in <repo root>.
For a PR: `gh pr view <n> --json title,body,commits`, `gh pr view <n> --comments`,
`gh api 'repos/{owner}/{repo}/pulls/<n>/comments' --paginate` for review
threads, and `gh pr diff <n>`. For a branch: its `git log` and diff against the base.
Commit messages and review threads hold the reasons the diff does not show.

Write <scratchpad>/problem.md with exactly three sections:
  ## Goal         what must be true for users or operators afterwards
  ## Constraints  what any solution must respect: compatibility, scale,
                  platforms, deadlines the source states, and guarantees the
                  system already gives that must keep holding (an
                  acknowledged write is never lost, a read never sees stale
                  data, ...)
  ## Done when    checks someone outside the code can run: a request, a
                  command, a log line, a query result
problem.md names no type, function, file, library or mechanism from the
change. It describes the need, as an issue would before anyone wrote code:
what must hold, not how.

Write <scratchpad>/current.md: the approach this change takes, in five lines
or fewer, then its costs as a list.

Reply with only the two paths.
```

Show `problem.md` to the user and ask them to confirm or correct it. A wrong problem makes every alternative wrong.

## Step 2 — Propose Blind

A merged or pushed change is already in the tree, and an agent that explores the tree finds it. A worktree is not enough: it shares the repo's history, so `git log main` still shows the change. Give the agent a plain copy of the files from before the change:

```bash
BASE=$(gh pr view <n> --json baseRefOid -q .baseRefOid)   # PR, open or merged
BASE=$(git merge-base <base-branch> <branch>)             # branch
BASE=HEAD                                                 # design doc
mkdir -p "$SCRATCHPAD/challenge-base"
git archive "$BASE" | tar -x -C "$SCRATCHPAD/challenge-base"
```

Dispatch a second fresh agent. Its prompt contains `problem.md`'s path and that checkout, and nothing about the change:

```
Read <scratchpad>/problem.md. Explore <scratchpad>/challenge-base as needed.

Write <scratchpad>/approaches.md with 2 or 3 approaches. Each one:
  ### <name>
  Idea:        two or three sentences
  Lives in:    which components or layers change
  Costs:       size of change, new dependencies, new invariants
  Gives up:    what it does worse
  Differs by:  where | mechanism | scope — how it differs from the others
Two approaches that differ only in parameters or library choice are one
approach. One approach solves a smaller or different version of the problem,
and says what it leaves unsolved.

Reply with only the path, then wait.
```

## Step 3 — Compare

Send the same agent `current.md`:

```
Read <scratchpad>/current.md: the approach actually taken. Write
<scratchpad>/comparison.md with exactly these parts:
  1. A table. Rows: Current, then each of your approaches.
     Columns: Approach | Lives in | Differs by | Costs | Gives up
  2. Recommendation: one paragraph. "Keep current" is a valid answer.
  3. Would change the recommendation: one line.
Reply with only the path.
```

## Step 4 — Relay

Show the user the confirmed problem, then `comparison.md` as written. Stop both agents with `TaskStop` and delete `challenge-base`. Offer `grill-me` on the approach they pick.

## Common Mistakes

| Mistake | Effect |
|---|---|
| Putting the PR title, diff or `current.md` in the step 2 prompt | Alternatives become variations of the PR |
| Pointing step 2 at the main checkout, or a worktree of it | The agent finds the change in the tree or the history and lists it as an alternative |
| Skipping the user's check of `problem.md` | Alternatives solve the wrong problem |
| Generating the alternatives yourself after reading the PR | Same anchoring the skill exists to remove |
| Adding bug findings or review comments to the output | That is `self-review`'s job; it buries the comparison |
