---
name: self-review
description: Use when your own changes are written and you are about to push, open a PR, or call the work done - reviewing your own branch diff rather than someone else's. Also when asked to self-review, double-check my own changes, or sanity-check a branch before sending it out.
---

# Self Review

Reviewing your own branch before it goes out. The bug classes are the same as any review. The failure mode is not.

## The Failure Mode

You already believe this code is correct. You wrote it, it compiles, it works on your machine. So you skim it, and what you actually read is your *intention* — not the diff.

You cannot fix this by trying harder. Intent is not something you can choose to stop knowing.

**So don't review it yourself.** Fan the passes out to agents with fresh context. An agent that never saw the code written cannot read intention into it — it can only read the diff. That is the whole design.

## Your Role: Blind Orchestrator

You do four things: **snapshot**, **dispatch**, **merge**, **verify**. You do not read the diff.

This is not a suggestion about attention. If you read the code, you form opinions, and those opinions become the filter at merge time — which is exactly where a biased filter does the most damage, because it silently deletes work the fresh agents already did correctly.

**Never dispatch with `subagent_type: "fork"`.** A fork inherits your full context, including having written the code under review. It is the one agent type guaranteed to be biased. Use `general-purpose`.

## Step 1 — Snapshot

Capture the target once, so every agent reviews an identical, immutable artifact.

```bash
SNAP="$SCRATCHPAD/self-review-$(date +%s).diff"   # scratchpad dir from your system prompt
# An open PR's base is the parent branch in a stack; fall back to the default branch.
BASE=$(gh pr view --json baseRefName -q .baseRefName 2>/dev/null)
BASE=${BASE:-$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')}
BASE=${BASE:-main}
{
  echo "### committed on branch (vs $BASE)"; git diff "$BASE...HEAD"
  echo "### uncommitted"; git diff HEAD
  echo "### untracked"; git ls-files --others --exclude-standard
} > "$SNAP"
gh pr view --json title,body -q '"# " + .title + "\n\n" + .body' > "${SNAP%.diff}.pr.md" 2>/dev/null \
  || rm -f "${SNAP%.diff}.pr.md"
wc -l "$SNAP" "${SNAP%.diff}.pr.md" 2>/dev/null
# Shape only, no code: changed-line count, then changed paths.
grep -cE '^[+-]([^+-]|$)' "$SNAP"
{ grep '^+++ b/' "$SNAP" | sed 's|^+++ b/||'; sed -n '/^### untracked/,$p' "$SNAP" | tail -n +2; } | sort -u
```

**Redirect to the files. Do not print them, `cat` them, or page them.** The `wc -l`, the line count and the path list are all you look at. If the diff is empty, stop and say so.

The `.pr.md` file exists only when the branch has an open PR. Only the omissions agent gets it, as a second artifact to check against the diff. It is never context for the other agents.

State the resolved target and the snapshot path to the user before dispatching.

## Step 2 — Dispatch

| # | Agent | Asks of the diff | Reads beyond it |
|---|---|---|---|
| 1 | **bugs** | *(runs `adversarial-code-reviewer`)* Then: does every consumer of changed shared state see the change? What does each new call cost per request, and what does each new log line do on its second tick? Does each new endpoint check what its closest sibling checks? | Call sites, error paths, every reader of changed state, the closest sibling endpoint |
| 2 | **look-and-feel** | Does each comment say something the code cannot, and does each doc comment state the contract rather than why it was built? Is any comment stale after this change? For every new or renamed type, function, constructor, file-level variable and config key: propose the best name you can, then report each one where yours beats the current name — what it does now, no stutter with its package, no word that says less than the code does. Could a reader tell which lines are new by style alone? | The three nearest files to each changed file; the package's `errors.go` and config validation |
| 3 | **existence** | Does this dependency already exist in the tree or the stdlib — and is it latest stable? Was this mechanism invented, or found — in the tree, in a lower layer of the same call path, or in a sibling service? | `go.mod`; greps the tree for prior art; the sibling service's equivalent code, build and deploy files |
| 4 | **tests** | For each test: which bug in the code under test would make it fail? Does it assert only what the code under test owns, and only what no other test already covers? Then: `require`, an `xxx_test` package, table-driven? | The code under test; neighbouring `*_test.go` files |
| 5 | **omissions** | What does this diff imply should also have changed, and didn't? Does the PR description still match the diff, and does the diff hold only this PR's change? | Callers, docs, help text, config samples, the `.pr.md` file when it exists |
| 6 | **simplify** | Argue that this diff is more complicated than it needs to be. For every new type, interface, function, file, config key, field, parameter, return value and goroutine: who uses it today? Where would deleting, inlining, hardcoding, flattening or a stdlib call leave the code shorter and no less clear? Which near-copies must change together and should merge? Which function does several unrelated jobs and should split by job? | Every caller of each new symbol; the code each near-copy duplicates; config samples, chart values |
| 7 | **layering** | For each new piece of logic: which layer owns this kind of work, and is that where it landed? Does an upper layer reach past the layer below it? Does a lower layer now know about an upper layer's concepts? Does each piece live in the package and file where its kind already lives? | The full call chain of each changed function, top to bottom; how two or three sibling operations split the same work across layers |

### Pick the Roster

Choose from the line count and path list. Nothing else — you have not read the diff.

- Under 40 changed lines: **bugs**, **omissions** and **simplify** only.
- Otherwise all seven, minus:
  - **tests** when no `*_test.go` file changed. Missing tests belong to omissions.
  - **layering** when every changed file sits in one directory.

When unsure, run the agent. Say which agents you skipped and why.

Issue the roster in a **single message** so it runs concurrently. Model: `opus`.

### When Axes Collide

The axes are ordered, not parallel. Higher wins, and the agent reports the ruling rather than the raw finding. Put this in the Doctrine slot of every dispatch:

1. **Correctness.** A bug outranks every style rule.
2. **Surroundings.** Matching the neighbours outranks every other doctrine rule, the comment cap included — a 4-line doc comment in a file of 4-line doc comments is correct.
3. **Prior art.** Using what already exists outranks writing something better.
4. **Everything else** — comments, simplification, tests, dependencies.

An axis that comes back empty is a result, not a failure. A diff that touches no dependency has nothing to say about latest-stable: say so and move on.

### Dispatch Prompt Contract

Every dispatch prompt has exactly these five parts, in this order:

1. **Target** — the snapshot path, and the repo root to read from.
2. **The question** — that agent's row above, verbatim.
3. **Reach** — what to read beyond the diff.
4. **Doctrine** — nearest `CLAUDE.md`, then the repo style guide, then `~/.claude/skills/adversarial-code-reviewer/reference/`.
5. **Output** — a report file to write, the finding block, severity-ordered, a "checked and clear" list, and that "no findings" is a valid result.

A thorough agent on a large diff overruns the message limit and its report arrives truncated, costing a round-trip each time. Give every agent a file path to write and ask it to reply with the path and its counts only.

Require the "checked and clear" list. Silence alone is indistinguishable from not having looked, and the list is what stops the next agent re-raising what this one already cleared.

Five parts. The authorial rationale — why the change exists, what it is for, what you were trying to do — is not one of them, and putting it in hands the agent your bias in the first paragraph. The omissions agent's `.pr.md` is the one exception: it gets the description as a claim to check against the diff, labelled that way in its Reach slot.

Template:

```
Review a diff against one specific question. You did not write this code and
have no information about why it exists. Judge only what is on the page.

TARGET:   <snapshot path>  (repo root: <path>)
QUESTION: <the agent's row, verbatim>
REACH:    <what to read beyond the diff>
DOCTRINE: <nearest CLAUDE.md>, then <style guide>, then
          ~/.claude/skills/adversarial-code-reviewer/reference/
          Measure the convention in this repo; do not quote remembered counts.
          When two rules collide: correctness > surroundings > prior art >
          everything else. Report the ruling, not the raw finding.

OUTPUT: write your full report to <scratchpad>/<agent>-report.md. Reply with
only that path, your total finding count, and the count by severity.

Report a finding only if a reviewer would ask for the change before approving.
Severity is what happens if it ships:
  CRITICAL  data loss, a security hole, or an outage
  HIGH      wrong behaviour a user or operator will hit
  MEDIUM    a reviewer blocks on it: a broken convention, a test that proves
            nothing, a name or comment that misleads
Everything below that bar goes in a "Nits" list after the findings, one line
each: `path:line — what to change`.

Every finding needs evidence. Quote the line that makes it true. A claim about
behaviour names the input that triggers it. A claim that other code is affected
names that code. No quote, no finding.

Report only what this diff introduces or makes worse. A problem that was
already there goes in a "Pre-existing" list after the nits, one line each.

Do not report what the compiler, formatter or `make lint` would catch.

In the file, one block per finding, CRITICAL first:

**VIOLATION: [short title]**
File: path:line
Doctrine: [which rule]
Severity: CRITICAL | HIGH | MEDIUM
Evidence: [the quoted line; the input or the affected code for a behaviour claim]
[what is wrong and what the doctrine requires]
Fix: [minimal corrective action]

End the file with "Checked and clear": what you examined and cleared, and why.
Name what you deliberately did not report, so another pass does not re-raise it.

Return "No findings" if the diff clears your question. Do not manufacture
findings to appear thorough. Report only on your question. Each problem has
one owner:
  bugs           behaviour that is wrong
  look-and-feel  names, comments, style the linter does not check
  existence      dependencies, and mechanisms that already exist elsewhere
  tests          the tests in the diff
  omissions      what should have changed and didn't
  simplify       code that should not exist, or should be smaller
  layering       which layer, package and file new code belongs in
```

Agent 1 substitutes its body with: *invoke the `adversarial-code-reviewer` skill against the target, then answer the rest of the bugs row* — it carries its own process and `BUG:` format. The bar, the evidence rule, the pre-existing rule and the Nits list still apply to it.

Agent 5 reports `MISSING:` blocks instead:

```
**MISSING: [short title]**
File: path:line  (or: no file — this was never written)
Severity: HIGH | MEDIUM
[what isn't there, and what depends on it]
Fix: [write it, or record it as an explicit deferral]
```

Agent 6 adds ponytail's review rules to its Doctrine slot when the plugin is installed:
sections 2.6 (Lean) and 3 (Check before you report) of
`~/.claude/plugins/cache/ponytail/ponytail/*/skills/ponytail-review/SKILL.md`. Its other
sections belong to other agents.

Agent 6 reports `SIMPLIFY:` blocks instead. It argues one side on purpose; the merge keeps every block that clears the bar, and the user rules on them:

```
**SIMPLIFY: [short title]**
File: path:line
Severity: HIGH | MEDIUM
Current: [what exists, and who uses it today]
Simpler: [delete | inline | hardcode | flatten | stdlib | merge | split, in one or two lines of sketch]
Saves: [lines, files, config keys or types removed]
Costs: [what the simpler form loses; "nothing" is a valid answer]
```

## Step 3 — Merge, Don't Adjudicate

The agents raise the same problem from different angles, and each pads its report with what sits just under the bar. A fresh agent merges them. Dispatch it once every report file exists:

```
Merge these review reports of one diff into a single list. You did not write
the code and have no information about why it exists.

INPUT:  <every report path>  (repo root: <path>)
        Read code only to decide whether two findings are one problem, or
        whether a finding clears the bar.
TASK:
- One problem, one entry. Findings at the same code that the same fix would
  satisfy become one entry: the clearest title and body, the highest severity,
  and a `Raised by:` line naming every agent.
- The bar. An entry stays a finding only if a reviewer would ask for the change
  before approving. Move every other entry to the nits, marked `(demoted)`.
- Contradictions. When one agent asks for what another rejects, or clears what
  another flags, write one entry with a `Disputed:` line giving both positions.
- Nothing else leaves. Every finding is in the list, merged into an entry, or
  in the nits.

OUTPUT: write <scratchpad>/merged.md with five sections:
  ## Findings     CRITICAL, then HIGH, then MEDIUM; each entry in its agent's
                  block format plus `Raised by:`
  ## Fix together entries that touch the same code, so one fix can't delete
                  the site another fix needs
  ## Nits         every agent's nits and every demoted finding, deduped, one
                  line each: `path:line — what to change (agent)`
  ## Pre-existing the agents' pre-existing lists, deduped
  ## Checked and clear  the agents' lists, deduped
Reply with only the path, the finding count by severity, and the nit count.
```

## Step 4 — Verify

The merge decides what is one problem. It does not decide what is true. A wrong finding that reaches the fixer gets applied. One more fresh agent checks every entry under `## Findings`:

```
Check each finding in a code review against the code. You did not write the
code or the review. False positives are common; do not feel pressure to confirm.

INPUT:  <scratchpad>/merged.md, the snapshot <path>  (repo root: <path>)
For each entry under "## Findings", answer three questions from the code:
  1. Is it real? Re-read the quoted line and trace the claim yourself.
  2. Did this diff introduce it, or make it worse?
  3. Is it already handled somewhere the reviewer did not look?
Judge each entry on its own; one verdict must not sway another.
When in doubt, reject.

OUTPUT: write <scratchpad>/verified.md: merged.md with every finding kept in
place and given a `Verified:` line naming what you checked, except:
  - an entry that fails 1 or 3 moves to a new "## Rejected by verifier"
    section, with a `Rejected:` line giving the reason
  - an entry that fails 2 moves to "## Pre-existing"
Nothing is deleted. Reply with only the path and the count of kept, rejected
and pre-existing entries.
```

Relay `verified.md` to the user: the findings in full, then the rejected entries with their reasons, then the nits and the pre-existing items as lists.

**You may not drop or re-rate what the merge and the verifier return.** You did not read the code, so you are not equipped to overrule an agent that did. If a finding looks wrong, it still goes in the report — with a `Disputed:` line saying why:

```
Disputed: agent 3 flags this as an invented retry loop; pkg/x already has one
at retry.go:20 but it is bounded differently. Worth your call.
```

A finding you delete is indistinguishable from a finding you never got. A disputed finding is still in front of the person who can settle it. A rejected finding stays in front of them too.

Once `verified.md` is on disk, stop every agent you started with `TaskStop`, then confirm with `ListAgents`. Reports first, then stop: an agent whose report you only have inline, and truncated, takes the rest of it with it.

## Step 5 — Hand Off

`verified.md` becomes the file a fixing agent works from without this conversation. Add the repo root, the module root if they differ, and the verify command.

Tag every finding, because a fixer that cannot tell them apart will guess on the ones that matter most:

- `[mechanical]` — the fix is stated; apply it.
- `[needs decision]` — a product or cross-repo choice. Stop and ask.
- A `SIMPLIFY:` block is `[mechanical]` when its Costs line is "nothing", otherwise `[needs decision]`.
- `[disputed]` — two reviewers disagreed. Record both positions; do not let the fixer pick one silently.
- Rejected and pre-existing entries get no tag. The fixer does not act on them unless the user says so.

Keep the merge's "Fix together" section at the top. Independent agents produce independently-correct fixes that destroy each other — the cheap one lands first and deletes the site the other two needed.

Keep the "checked and clear" section too, so the fixer does not re-derive what the agents already cleared.

Save the tagged file where it outlives the scratchpad, and give the user its path:

```bash
DIR=~/code/treeverse/knowledge/self-review; mkdir -p "$DIR"
OUT="$DIR/$(date +%F)-$(basename "$(git rev-parse --show-toplevel)")-$(git branch --show-current | tr '/' '-').md"
n=2; base=${OUT%.md}; while [ -e "$OUT" ]; do OUT="$base-$n.md"; n=$((n+1)); done
cp <scratchpad>/verified.md "$OUT" && echo "$OUT"
```

If you created a worktree for the review, say where it is and leave it — the fixer will want it. Remove it with `git worktree remove <path>` once the findings are worked.

## Rationalizations

The agents aren't biased — they've never seen your intent. **You are**, and you become biased again the moment the findings come back and you start defending the code. These are the thoughts that appear at merge and fix time.

| You'll think | Reality |
|---|---|
| "The agent didn't understand what I was doing" | It wasn't supposed to. If the code only reads correctly with your intent supplied, that's the finding |
| "That comment is genuinely subtle" | Then the *code* is the problem. Rename or restructure first; comment only what stays subtle after |
| "My way is cleaner than the surrounding code" | Consistency beats a local optimum. Match the neighbours, or change the whole file in its own commit |
| "I'll clean it up in a follow-up" | Write the follow-up down now, or do it now. Otherwise it isn't real |
| "Simplify is just playing devil's advocate" | That is its job. Relay every block; the user rules on them |
| "The verifier rejected it, so I can leave it out" | Rejected entries are relayed with their reason. The user may know better than the verifier |
| "I'll just drop that one, it's noise" | You didn't read the diff. Dispute it in writing; don't delete it |

## Go and lakeFS Specifics

Hand these to agents through the Doctrine slot; don't paraphrase them into the prompt.

- **Assertions:** `require` fatal, `assert` non-fatal. Legacy `t.Errorf`/`t.Fatalf` is volume, not precedent.
- **Test package:** external `xxx_test` (`package graveler_test`). `docs/go-style-guide.md` still says same-package for unit tests; that line is stale, follow the tree. `export_test.go` in the package's own name is the standard idiom, not a violation.
- **Measure, don't quote.** Have the agent count the convention in the repo under review — `reference/go.md` carries per-repo baselines, and lakeFS-Enterprise and cloud-controlplane differ.
- **Tables:** table-driven by default. Verify core behaviour clearly rather than one test per error path.
- **Errors:** `errors.Is`, never message comparison. Needing one means the package owes the caller a distinct error value.
- **Comments:** timeless. No PR, ticket, or prior-behaviour references. Why a change was made belongs in the commit message.
- **Layers:** in lakeFS core, each layer calls only the one below it. Services and cloud-controlplane have their own stacks; measure those from sibling operations.
  - API controller (`pkg/api`): authorization, request parsing, response shaping
  - catalog (`pkg/catalog`): maps API concepts onto graveler; owns entry and metadata semantics
  - graveler (`pkg/graveler`): versioning — refs, commits, staging, merge
  - kv / block (`pkg/kv`, `pkg/block`): persistence

## No Subagents Available?

Running inside an agent that can't dispatch, review the passes yourself in the table's order, one at a time, finishing each before starting the next. Then re-check every finding against the three verify questions. Say plainly in the report that it was a single-context review — the bias the skill exists to remove was not removed.

## Red Flags — Stop

- You read the diff (`cat`, `git diff` to stdout, opening a changed file)
- You dispatched with `subagent_type: "fork"`
- You put "what this change is for" into a dispatch prompt
- You dropped or re-rated an entry instead of disputing it
- You handed the fixer `merged.md` without running the verifier
- Every agent returned "No findings" on a diff over 200 lines
