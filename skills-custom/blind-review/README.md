# blind-review

A blind, multi-agent code review for your own branch or a PR. The orchestrating session
never reads the diff; fresh agents do, a merge agent dedups, a verifier re-checks every
finding against the code, and each review is saved as a round in the branch's history
under `.git/blind-review/<branch>/`. The result comes back in chat and as Markdown.

Delivering it elsewhere is optional and lives in separate skills:
- `review-to-artifact`: one shared page per branch, where teammates tick findings resolved
- `review-to-difftool`: inline comments on a difftool review

## Install

Copy this directory to `~/.claude/skills/blind-review/` (personal) or to a repo's
`.claude/skills/blind-review/` (shared with everyone who clones it). A plugin in
`treeverse/dev` is the intended long-term home.

Needs: `gh` authenticated, `jq`, `python3`, and a Claude Code session that can spawn
subagents. Without subagents it degrades to a single-context review and says so.

If you have a personal `self-review` skill installed, remove it: both answer to
"self-review".

## Use

- On your branch, before pushing: `/blind-review`
- Stacked on another branch: `/blind-review --base feature/1234-parent`
- A PR: `/blind-review 4271` or `/blind-review https://github.com/treeverse/lakeFS-Enterprise/pull/4271`
- Again after fixing: `/blind-review` — saves r2, with a fixed / not fixed / waived account
  of every r1 finding. A local review and a later PR review of the same branch share one
  history.

## What it costs

Under 40 changed lines: 3 or 4 finder agents + merge + verify. Otherwise up to 7 finders
+ merge + verify. bugs, removed, risk and verify run on the session's model; the rest run
on Sonnet. Say "all sonnet" or "all opus" to override. Before the team relies on the
split, run one diff both ways and compare what each finds; numbers belong here once we
have them.

## Why blind

You already believe your code is correct, so what you read is your intention, not the
diff. The orchestrator therefore never sees the code; it moves files between agents that
have no idea why the change exists. The only agent that hears what the change is *for* is
the intent agent, and it hears it as a claim to test.

## Doctrine

Repo conventions come from each repo's `CLAUDE.md` at run time plus
`reference/doctrine-lakefs.md` here. Add a rule to the reference file only when an agent
could not have measured it from the tree.
