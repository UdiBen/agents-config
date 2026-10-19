# Test-pruning campaign

Campaign mode prunes one subsystem's whole test surface in one PR: a plugin, a package, or
one core area. The authoring gate, retention bar, and candidate evidence in
[SKILL.md](SKILL.md) and [references/audit.md](references/audit.md) apply to every lane.
This file adds the order of work. Each step ends on its completion criterion; start the
next step only once it is met.

## 1. Baseline

Pin a main-branch SHA. Record the subsystem's test and support line counts and every test
file's pass/fail state. Keep baseline failures in their own list: they are often real
product bugs, not stale tests.

Done when every in-scope test file has a recorded baseline result.

## 2. Lanes and inventory

Split the surface into **lanes** along production owner boundaries, not file prefixes
(for example: accounts, commands, dispatch, inbound, outbound, persistence, transport,
shared harness, live/QA scenarios). Include the subsystem's cases at shared core
boundaries and its QA and live-proof harness tests.

Done when every test file and QA scenario the subsystem owns belongs to exactly one lane.

## 3. Read-only ledger per lane

Give each lane to its own read-only agent. It reads every assigned test in full, including
parameter tables, plus the production owners, entry points, callers, history, and CI
routing. Each test declaration gets one mark in a written **ledger**. A table-driven test
is one declaration unless its rows need different marks.

- `R` retain: name the contract and the bug it catches; a move to a better file stays `R`
- `F` fix: keep the contract, repair the assertion (e.g. a vacuous negative)
- `C` consolidate: name the owner that absorbs the assertion first
- `D` delete: name the proof that remains, or why no contract exists

Judge a test by its assertions, not its name.

Done when every declaration in the lane has a mark and an evidence line.

## 4. Layer plan per lane

The ledger is input, not the edit list. A second read-only pass looks for the redundant
**layer**: suites replaying the same shared logic through a mock around stronger
real-boundary suites. Name the **keeper** suite for each contract. Prefer the real
transport boundary with a fake network over a mocked collaborator. Correct ledger errors
this pass finds.

Done when each lane plan names its retired files, its keeper per contract, the assertions
to carry into keepers, and the test-only production seams unlocked.

## 5. Cutover

Edit lane by lane. Serialize changes to shared harnesses and support files through one
owner. With each lane, remove the test-only production seams it unlocks: injection
parameters, getters, reset exports, indirection layers. Register moved suites in CI
routing and test inventories. Put durable test-ownership rules in the subsystem's
`AGENTS.md`/`CLAUDE.md`, drawn from mistakes this campaign actually found.

Done when every lane plan is applied and each lane's keepers pass.

## 6. Preservation review

Independent reviewers, one per boundary group, compare deleted coverage against the
keepers. They hunt for contracts that lost their only proof, and for new assertions that
cannot fail (a rejection row production never reaches).

For each restored contract, make one deliberate **mutation** of the production owner and
confirm the keeper goes red. Then restore the source byte for byte.

Done when every reported gap is restored or rejected with source evidence, and every
restored contract has a caught mutation.

## 7. Product defects

A baseline failure that survives into a keeper is a bug report. Fix it at its owner as a
separate commit, proven through the real user flow with a **control** run that reverts the
fix and shows the old behavior. Record unrelated discrepancies as follow-ups.

Done when each repaired defect has a failing control and a passing candidate on the same
harness.

## 8. Reconcile and hand off

Campaigns outlive many main-branch commits. Merge main rather than rebasing a long
campaign. When main modified a file the campaign deleted, keep the deletion and port the
new contract into the keeper. Confirm every regression main added still has a home. Let PR
CI rerun the broad suite; locally rerun only tests touched by the merge or failed in CI.

Review tooling may show a truncated file list on a diff this large; record maintainer
decisions in the PR evidence.

Hand off with the [SKILL.md report](SKILL.md#report), plus:

- baseline and final test/support line counts, production counted separately
- lanes, retired layers, and keepers
- preservation gaps found and their mutations
- product defects with control and candidate proof

---
Adapted from [openclaw/openclaw](https://github.com/openclaw/openclaw/tree/71b5563/.agents/skills/test-audit) (MIT).
