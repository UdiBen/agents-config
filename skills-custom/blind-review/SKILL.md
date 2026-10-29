---
name: blind-review
description: >-
  Blind, multi-agent code review of a changeset — your own branch before you push, or a
  GitHub PR. Use when asked to "self-review", "review my branch", "review before I push",
  "sanity-check this before the PR", "review PR #N", or as the QA gate before opening or
  merging a PR. The orchestrator never reads the diff: it snapshots it, dispatches fresh
  agents (bugs, removed behaviour, tests, risk, conventions, lean, intent/cross-repo),
  merges, proves every behaviour claim with a test that fails on the change, and saves the round to the
  branch's history so a re-review accounts for every earlier finding. Results go to chat
  and Markdown; review-to-artifact and review-to-difftool deliver them elsewhere.
  Read-only toward the reviewed repo: never commits, pushes, posts to GitHub or edits
  tracked files.
---

# blind-review

Reviewing a changeset — **yours** (the default) or **someone else's PR** — with agents that
have never seen the code written. One pipeline, five steps: **snapshot → dispatch →
merge → prove → save**. The reference files and scripts carry the details; this file
is the contract. Delivering the result anywhere other than chat is a separate skill's job.

| File | What it holds |
|---|---|
| `scripts/snapshot.sh` | Resolves the target and writes the run directory: snapshot, claims, `env.sh` |
| `scripts/proof.py` | Splits the merged list into proof tasks, and assembles the verdicts into `verified.json` |
| `scripts/save_round.py` | Reads the previous round, and saves the next one as `r<N>.json` and `r<N>.md` |
| `reference/changeset.md` | Targets, the run directory, stacked bases, batches |
| `reference/prompts.md` | The seven agent rows, the dispatch template, the merge, prove and static check prompts |
| `reference/report.md` | Round history, tags, verdict, the round record, delivery |
| `reference/doctrine-lakefs.md` | Treeverse/lakeFS doctrine handed to agents (Go, layering, cross-repo, Enterprise) |

## Why the orchestrator is blind

You already believe this code is correct, and so does any agent that helped write it.
What you read is your intention, not the diff. You cannot fix that by trying harder, so
the design removes you from the loop: agents with fresh context read the diff; you only
move files between them. If you read the code you form opinions, and those opinions become
the filter at merge time, silently deleting work the agents did correctly.

This holds in PR mode too. Reviewing a colleague's PR you have no authorial bias, but you
do have the PR description, which is the author's bias handed to you. Stay blind; it costs
nothing.

## Hard rules

- **Never read the diff.** No `cat`, no `git diff` to stdout, no opening a changed file.
  You look at three things: the shape the snapshot script prints, the agents' reply
  counts, and the final `verified.json`.
- **Never dispatch with `subagent_type: "fork"`.** A fork inherits this conversation,
  including having written the code. Use `general-purpose`.
- **Never put the authorial rationale in a dispatch** — what the change is for, what you
  were trying to do. The one exception is the intent agent, which gets `claims.md`,
  **labelled as claims to test**, never as context.
- **Never drop or re-rate** what the merge, provers and static checker return. You did not read the code;
  you are not equipped to overrule an agent that did. Dispute in writing (`Disputed:`).
- **Read-only toward the reviewed repo.** No commit, push, checkout, stash, add, reset; no
  GitHub comments, approvals or labels; no edits to tracked files. Allowed: `git fetch`;
  the run directory, including the detached PR and base checkouts inside it; and the round history
  under the repository's git directory (`.git/blind-review/<branch>/`).

## Step 1 — Snapshot

```bash
<skill dir>/scripts/snapshot.sh <scratch root> [--base <branch>] [<pr>]
```

Details in `reference/changeset.md`. The script prints the run directory and the shape:
changed lines, changed paths, test paths, security-sensitive paths, issues found, and the
previous round, if any. Every later shell step starts with `source <run>/env.sh`.

If changed lines is 0, stop and say so. State the target, base, run directory and shape to
the user before dispatching. If no issue was found, ask the user what the change is for
and append the answer to `claims.md` (see `changeset.md`).

## Step 2 — Dispatch

Seven agents, each owning one question. Full rows and the template are in
`reference/prompts.md`.

| # | Agent | Owns | Model |
|---|---|---|---|
| 1 | **bugs** | Behaviour that is wrong: line-by-line scan, callers and callees, language pitfalls, wrapper routing, shared-state consumers, per-request cost | session |
| 2 | **removed** | For every deleted or replaced line, the invariant it enforced and where the new code re-establishes it | session |
| 3 | **tests** | Which bug makes each test fail; expected and unwanted behaviour covered; the regression test a fix owes | `sonnet` |
| 4 | **risk** | Security (authz, injection, secrets, validation, detection vs. prevention) and cost at the input scale where it bites | session |
| 5 | **conventions** | Names, comments, layering, CLAUDE.md rules it can quote | `sonnet` |
| 6 | **lean** | Code that should not exist or should be smaller; mechanisms that already exist; dependency freshness | `sonnet` |
| 7 | **intent** | What should also have changed; the issue, no more and no less; cross-repo contracts and deploy order | `sonnet` |
| — | **merge** | Dedup into one list; nothing dropped | `sonnet` |
| — | **prove** | One per behaviour claim and question: a test that fails if the claim is true | session |
| — | **static check** | Text-based findings against the quoted line and rule; prior-round accounting | `sonnet` |

**Models.** "session" means omit `model`, so the agent runs on this session's model.
`sonnet` means pass `model: "sonnet"`. The agents where a miss ships a bug run on the
session's model; the rest run on Sonnet. When the user names a model for the whole review
("all sonnet", "all opus"), use it for every agent. Record what ran on what for the
report's `--models`.

**Roster by shape.**

- Under 40 changed lines: **bugs**, **removed**, **intent**, plus **risk** when any
  security-sensitive path changed.
- Otherwise all seven, minus **tests** when no test path changed (missing tests then
  belong to intent).

When unsure, run the agent. Say which you skipped and why.

**Batch** (several changesets): run Steps 1–4 per changeset, then one extra **intent**
dispatch that reconciles producer against consumer (`reference/changeset.md`).

Issue the roster in a **single message** so it runs concurrently. Every agent writes its
report to a file and replies with the path and its counts only; a thorough agent on a
large diff overruns the message limit otherwise.

## Step 3 — Merge

A fresh agent merges the report files into one list, `merged.json`: one problem, one
entry; findings under the bar demoted to nits; questions kept as questions;
contradictions kept as `disputed`; nothing deleted. Prompt in `reference/prompts.md`.

## Step 4 — Prove

The merge decides what is one problem. It does not decide what is true. A wrong finding
that reaches a fixer gets applied, so every behaviour claim is proven by running code
before it is reported.

1. Load the previous round and get the round number `N` (`reference/report.md`, "Before
   proving").
2. Split the list: `python3 -I <skill dir>/scripts/proof.py split --env <run>/env.sh`.
   It writes one proof task per behaviour claim (`BUG`, `RISK`, a `MISSING` test) and per
   question, lists the text-based findings for the static check, and checks out the base
   commit at `<run>/base` for the provers.
3. Dispatch, in **one message**, one **prover** per task and one **static checker**
   (prompts in `reference/prompts.md`). Skip the static checker only on a first review
   with nothing to check. With more tasks than free agent slots, dispatch in batches.
   - A prover writes the smallest test that fails if the claim is true and runs it on
     the change and on the base. Its verdict is `PROVEN`, `REFUTED`, `PRE_EXISTING`, or,
     rarely, `THEORETICAL`: the trigger is out of reach of any local test, and it says
     what is out of reach. It never touches the checked-out code; probes go in
     `<run>/proof/<mid>/` and run through Go's `-overlay` or a copy.
   - The static checker confirms or refutes the text-based findings against the quoted
     line and rule, and on a re-review accounts for every prior finding as fixed, not
     fixed or waived, mapping a finding that is still present to its prior id.
4. Assemble: `python3 -I <skill dir>/scripts/proof.py assemble --env <run>/env.sh --n <N>`.
   It writes `verified.json`. Refuted entries are kept with their reason; theoretical
   ones become the round's open questions; a claim with no result is kept as an open
   question, never dropped.

## Step 5 — Save

Save the round to the branch's history with `save_round.py` (`reference/report.md`). It
writes `r<N>.json`, the record delivery skills read, `r<N>.md`, and keeps the probe tests
in `r<N>-proof/` so whoever fixes a finding can start from its failing test. Then relay to
the user: the verdict line, the findings in full with their proof, what could not be
proven locally and why, the refuted entries with reasons, nit and pre-existing counts,
and the path of `r<N>.md`.

Then stop every agent you started (`TaskStop`) and confirm with `ListAgents`. Reports
first, then stop: an agent whose report you only have inline takes the rest of it with it.
Remove the base checkout (`git worktree remove --force <run>/base`) and, in PR mode, the PR
worktree unless the user wants it kept for fixing.

## After the report

Offer, do not do:

- **Fix** the findings — any agent may fix, including this conversation; fixing is not
  reviewing. Work "Fix together" entries as one change. `needs decision` and `disputed`
  entries stop and ask; `confirm first` entries are confirmed before they are fixed.
- **Re-review** — run this skill again; it saves the next round, with the prior-findings
  accounting.
- **Deliver** — `review-to-artifact` publishes the branch's rounds as one shared page where
  the team ticks findings resolved; `review-to-difftool` posts them as inline comments.
  Both read `r<N>.json` and are optional.
- **PR mode:** post selected findings as PR comments — draft first, post only on an
  explicit yes.

## Rationalizations

The agents are not biased; they never saw your intent. You are, and you become biased
again the moment the findings arrive and you start defending the code.

| You'll think | Reality |
|---|---|
| "The agent didn't understand what I was doing" | It wasn't supposed to. If the code only reads correctly with your intent supplied, that is the finding |
| "That comment is genuinely subtle" | Then the code is the problem. Rename or restructure first; comment only what stays subtle after |
| "My way is cleaner than the surrounding code" | Consistency beats a local optimum. Match the neighbours, or change the whole file in its own commit |
| "I'll clean it up in a follow-up" | Write the follow-up down now, or do it now. Otherwise it isn't real |
| "lean is just playing devil's advocate" | That is its job. Relay every block; the user rules on them |
| "The prover refuted it, so I can leave it out" | Refuted entries are relayed with their reason. The user may know better than the prover |
| "I'll just drop that one, it's noise" | You didn't read the diff. Dispute it in writing; don't delete it |
| "That's planned groundwork, the caller comes in a later issue" | Then the intent agent should have seen it in the parent issues. If it did not, the finding becomes a hand-off note, not a deletion |

## No subagents available?

Review the rows yourself in table order, one at a time, finishing each before the next.
Then prove each behaviour claim yourself as the prove prompt describes, write
`verified.json` yourself, and save the round with `--single-context`. The record and the
relay then say plainly that the bias this skill exists to remove was not removed.

## Red flags — stop

- You read the diff.
- You dispatched with `subagent_type: "fork"`.
- You put "what this change is for" into any dispatch but intent's claims slot.
- You dropped or re-rated an entry instead of disputing it.
- You handed a fixer `merged.json` without proving it.
- You accepted a `THEORETICAL` verdict that names nothing out of reach.
- You saved a round over an earlier one, or started a re-review from round 1.
- Every agent returned "No findings" on a diff over 200 lines.
