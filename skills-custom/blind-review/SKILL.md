---
name: blind-review
description: >-
  Blind, multi-agent code review of a changeset — your own branch before you push, or a
  GitHub PR. Use when asked to "self-review", "review my branch", "review before I push",
  "sanity-check this before the PR", "review PR #N", or as the QA gate before opening or
  merging a PR. The orchestrator never reads the diff: it snapshots it, dispatches fresh
  agents (bugs, removed behaviour, tests, risk, conventions, lean, intent/cross-repo),
  merges, verifies with a recall-biased three-state verdict, and publishes one rolling
  report page per branch where the team ticks findings resolved. Read-only toward the
  reviewed repo: never commits, pushes, posts to GitHub or edits tracked files.
---

# blind-review

Reviewing a changeset — **yours** (the default) or **someone else's PR** — with agents that
have never seen the code written. One pipeline, five steps: **snapshot → dispatch →
merge → verify → report**. The reference files and scripts carry the details; this file
is the contract.

| File | What it holds |
|---|---|
| `scripts/snapshot.sh` | Resolves the target and writes the run directory: snapshot, claims, `env.sh` |
| `scripts/build_report.py` | Reads the previous report, and builds the next iteration's page from `verified.json` |
| `reference/changeset.md` | Targets, the run directory, stacked bases, batches |
| `reference/prompts.md` | The seven agent rows, the dispatch template, the merge and verify prompts |
| `reference/report.md` | Tags, verdict, publishing the rolling page, the Markdown fallback |
| `reference/report.html` | The page template the build script fills |
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
- **Never drop or re-rate** what the merge and verifier return. You did not read the code;
  you are not equipped to overrule an agent that did. Dispute in writing (`Disputed:`).
- **Read-only toward the reviewed repo.** No commit, push, checkout, stash, add, reset; no
  GitHub comments, approvals or labels; no edits to tracked files. Allowed: `git fetch`;
  the run directory, including a detached PR worktree inside it; and the report index
  under the repository's git directory (`.git/blind-review/`).

## Step 1 — Snapshot

```bash
<skill dir>/scripts/snapshot.sh <scratch root> [--base <branch>] [<pr>]
```

Details in `reference/changeset.md`. The script prints the run directory and the shape:
changed lines, changed paths, test paths, security-sensitive paths, issues found, and the
previous report's URL. Every later shell step starts with `source <run>/env.sh`.

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
| — | **verify** | Three-state verdict on every finding; prior-iteration accounting | session |

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

A fresh agent merges the report files into one list: one problem, one entry; findings
under the bar demoted to nits; questions kept as questions; contradictions kept as
`Disputed:`; nothing deleted. Prompt in `reference/prompts.md`.

## Step 4 — Verify

The merge decides what is one problem. It does not decide what is true. A wrong finding
that reaches a fixer gets applied.

First find the previous iteration and its ticks, and get the next iteration number
(`reference/report.md`, "Before the verifier"). Then one fresh agent re-checks every
finding against the code with a **three-state verdict** (`CONFIRMED` / `PLAUSIBLE` /
`REFUTED`) and three questions: is it real, did this diff introduce it, is it handled
elsewhere. It is **recall-biased**: a realistic trigger is PLAUSIBLE, and REFUTED needs
proof constructible from the code. Refuted entries are **kept with their reason**, never
deleted. On a re-review it also accounts for every prior finding as fixed, not fixed or
waived, and flags ticked findings that are still present. It also settles every
question it can from the code, turning each into a finding or a refuted entry; only a
question the code cannot answer stays open, saying what would answer it. It writes
`verified.json`.
Prompt in `reference/prompts.md`.

## Step 5 — Report

Build the page and publish it to the branch's one rolling Artifact
(`reference/report.md`). Then relay to the user: the verdict line, the findings in full,
the open questions, the refuted entries with reasons, nit and pre-existing counts, and the
link.

Then stop every agent you started (`TaskStop`) and confirm with `ListAgents`. Reports
first, then stop: an agent whose report you only have inline takes the rest of it with it.
In PR mode, remove the worktree unless the user wants it kept for fixing.

## After the report

Offer, do not do:

- **Fix** the findings — any agent may fix, including this conversation; fixing is not
  reviewing. Work "Fix together" entries as one change. `needs decision` and `disputed`
  entries stop and ask; `confirm first` entries are confirmed before they are fixed.
- **Re-review** — run this skill again; it adds the next iteration to the same page, with
  the prior-findings accounting.
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
| "The verifier refuted it, so I can leave it out" | Refuted entries are relayed with their reason. The user may know better than the verifier |
| "I'll just drop that one, it's noise" | You didn't read the diff. Dispute it in writing; don't delete it |
| "That's planned groundwork, the caller comes in a later issue" | Then the intent agent should have seen it in the parent issues. If it did not, the finding becomes a hand-off note, not a deletion |

## No subagents available?

Review the rows yourself in table order, one at a time, finishing each before the next.
Then re-check every finding against the verifier's three questions, write
`verified.json` yourself, and build the report with `--single-context`. The page and the
relay then say plainly that the bias this skill exists to remove was not removed.

## Red flags — stop

- You read the diff.
- You dispatched with `subagent_type: "fork"`.
- You put "what this change is for" into any dispatch but intent's claims slot.
- You dropped or re-rated an entry instead of disputing it.
- You handed a fixer `merged.md` without running the verifier.
- You published a new artifact when the branch already had one.
- Every agent returned "No findings" on a diff over 200 lines.
