# Rounds and the round record

Each review of a branch is a round. Rounds are kept in the branch's history directory,
`HIST_DIR` in `env.sh`: `.git/blind-review/<branch>/` in the repository's shared git
directory, so every worktree of the repository sees the same history and nothing appears
in `git status`. A local review and a later PR review of the same branch share one
history. `scripts/save_round.py` writes each round and derives its tags and verdict, so
the orchestrator copies files and never judges a finding. `reference/deliver.md` delivers
a saved round to the terminal, an Artifact page or difftool.

## Tags and verdict

The tag is the verifier's `call`, never set by hand:

| Tag | When |
|---|---|
| `fix` | the defect is real and `how` states the fix |
| `skip` | not worth the change; `how` says why |
| `decide` | disputed, every `CONTRACT:`, a costly `SIMPLIFY:`, a product choice, or no call |

Verdict, counting only `fix` and `decide` findings: any CRITICAL → blocked; any HIGH →
needs changes; MEDIUM only → ship with nits; none → ship. Refuted, pre-existing and question entries carry no tag. Whoever fixes the
findings does not act on them unless the user says so.

## Before the verifier

```bash
python3 -I <skill dir>/scripts/save_round.py prev --env <run>/env.sh
```

It writes `<run>/prev.json`, the latest round's findings (`[]` on a first review), and
prints the next round number `N`. Ask the user which earlier findings they waive, by their
number in the previous round. `N`, `prev.json` and those numbers go into the verify prompt.

## After the verifier

```bash
python3 -I <skill dir>/scripts/save_round.py save --env <run>/env.sh \
  --roster "<agents run>" --skipped "<agents skipped and why>" --models "<who ran on what>" \
  --verify-cmd "<the test command the repo's CLAUDE.md names>" [--single-context]
```

It writes `HIST_DIR/r<N>.json` and `HIST_DIR/r<N>.md`, and never overwrites an earlier
round.

## The round record

`r<N>.json` is the contract every destination reads:

```
{repo, slug, n, date, target, head, base_ref, base, tree,
 roster, skipped, models, verify_cmd, single_context,
 verdict, verdict_note,
 prior:         [{key, fate: fixed|not_fixed|waived, note}],
 fix_together:  [{ids, note}],
 findings:      [{id, key, kind, title, severity, summary, evidence, repro,
                  verdict, verified, call, how,
                  file, line, raised_by, tag, fields: [[label, text], …],
                  disputed?: {for, against}, from_question?}],
 questions:     [{id, title, file, line, text, needs?, raised_by}],
 refuted:       [{id, title, file, line, reason, raised_by}],
 nits:          [{id, file, line, text, agent}],
 pre_existing:  [{id, file, line, text}],
 checked_clear: [text],
 batch?}
```

The script numbers every entry of a round from 1, shown as `#1`: findings in severity
order, then questions, refuted entries, nits and pre-existing items. The user refers to any
entry by that number, such as "fix 1, 7 and 9". Numbers restart each round. A finding that
survives from one round to the next keeps its `key`, so the review page can tell a new
finding from one that was already reported; the report never shows the key.
