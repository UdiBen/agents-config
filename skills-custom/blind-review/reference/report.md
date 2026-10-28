# Rounds and the round record

Each review of a branch is a round. Rounds are kept in the branch's history directory,
`HIST_DIR` in `env.sh`: `.git/blind-review/<branch>/` in the repository's shared git
directory, so every worktree of the repository sees the same history and nothing appears
in `git status`. A local review and a later PR review of the same branch share one
history. `scripts/save_round.py` writes each round and derives its tags and verdict, so
the orchestrator copies files and never judges a finding.

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

## Before the verifier

```bash
python3 -I <skill dir>/scripts/save_round.py prev --env <run>/env.sh
```

It writes `<run>/prev.json`, the latest round's findings (`[]` on a first review), and
prints the next round number `N`. Ask the user which earlier findings they waive. `N`,
`prev.json` and the waived ids go into the verify prompt.

## After the verifier

```bash
python3 -I <skill dir>/scripts/save_round.py save --env <run>/env.sh \
  --roster "<agents run>" --skipped "<agents skipped and why>" --models "<who ran on what>" \
  --verify-cmd "<the test command the repo's CLAUDE.md names>" [--single-context]
```

It writes `HIST_DIR/r<N>.json` and `HIST_DIR/r<N>.md`, and never overwrites an earlier
round.

## The round record

`r<N>.json` is the contract delivery skills read:

```
{repo, slug, n, date, target, head, base_ref, base, tree,
 roster, skipped, models, verify_cmd, single_context,
 verdict, verdict_note,
 prior:         [{id, fate: fixed|not_fixed|waived, note}],
 fix_together:  [{ids, note}],
 findings:      [{id, kind, title, severity, verdict, verified, file, line,
                  raised_by, tag, fields: [[label, text], …],
                  disputed?, from_question?}],
 questions:     [{title, file, line, text, needs?, raised_by}],
 refuted:       [{title, file, line, reason, raised_by}],
 nits:          [{file, line, text, agent}],
 pre_existing:  [{file, line, text}],
 checked_clear: [text],
 batch?}
```

A finding that survives from one round to the next keeps its id, so a delivery skill can
tell a new finding from one that was already reported.

## Delivery

The round's Markdown and the chat relay are the default. Two optional skills deliver
elsewhere, both from `r<N>.json`:

- `review-to-artifact` publishes every round of the branch as one shared page where the
  team ticks findings resolved.
- `review-to-difftool` posts the findings as inline comments on a difftool review.

## Relay to the user

In chat, in this order: the verdict line; the findings, in full; the open questions; the
refuted entries with their reasons; nits and pre-existing items as counts; the path of
`r<N>.md`. No praise, and no summary of what the change does: the author already knows.
