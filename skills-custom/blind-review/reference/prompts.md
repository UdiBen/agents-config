# Dispatch, merge and verify prompts

Every prompt is self-contained: the agent sees none of this conversation. The orchestrator
fills the angle-bracket slots and nothing else. "Verbatim" means verbatim.

## Dispatch template

Five parts, in this order. The authorial rationale is not one of them.

```
Review a diff against one specific question. You did not write this code and
have no information about why it exists. Judge only what is on the page.

TARGET:   <snapshot path>   (repo root: <AGENT_ROOT>)
          It has a "### committed" section and, for a local branch, "### uncommitted"
          and "### untracked". Every section is the change under review.
QUESTION: <the agent's row below, verbatim>
REACH:    <the agent's reach, verbatim> — read it from the repo root; never trust the
          diff's context lines for anything outside the hunk.
DOCTRINE: <nearest CLAUDE.md to each changed file, then the repo style guide if any,
          then <skill dir>/reference/doctrine-lakefs.md>.
          Measure the convention in this repo; do not quote remembered counts.
          When two rules collide: correctness > surroundings > prior art >
          everything else. Report the ruling, not the raw finding.

OUTPUT: write your full report to <run>/<agent>-report.md. Reply with
only that path, your total finding count, and the count by severity.

Mindset: assume the code is broken and prove it. No compliments. If it looks
wrong, say it is wrong and construct the trigger. A claim that rests on library,
runtime or pinned-version behaviour you could not check, by running it or by
reading the source at the pinned version, is a QUESTION block, never a finding.
The verifiers try to prove every QUESTION by running code.
Trace the code before you write one: a QUESTION is for what the code cannot
settle, not for a route you did not finish following.
Report a finding only if a reviewer would ask for the change before approving.
Severity is what happens if it ships:
  CRITICAL  data loss, a security hole, or an outage
  HIGH      wrong behaviour a user or operator will hit
  MEDIUM    a reviewer blocks on it: a broken convention, a test that proves
            nothing, a name or comment that misleads
Everything below that bar goes in a "Nits" list after the findings, one line
each: `path:line — what to change`.

Every finding needs evidence. Quote the line that makes it true. A claim about
behaviour names the input, state, timing or sequence that triggers it. A claim
that other code is affected names that code. No quote, no finding. Pass every
candidate with a nameable trigger through — a finder that silently drops
half-believed candidates bypasses the verifier and is the main cause of misses.

Report only what this diff introduces or makes worse. Bugs on unchanged lines of
a touched function are in scope only if the change re-exposes them or was
supposed to fix them; say which. A problem that was already there goes in a
"Pre-existing" list after the nits, one line each. Check the base when unsure:
`git grep` the construct on <BASE>.

Do not report what the compiler, formatter or `make lint` would catch.

Line numbers: derive every `path:line` from the file itself (`grep -n` in the
repo root), never from the diff's position. No anchor may exceed the file's
line count.

In the file, one block per finding, CRITICAL first:

**<KIND>: [short title]**
File: path:line
Severity: CRITICAL | HIGH | MEDIUM
Evidence: [the quoted line]
Trigger: [the input / state / sequence that hits it]      ← BUG
Doctrine: [the rule, quoted, and where it is written]      ← VIOLATION
[what is wrong, one or two sentences]
Fix: [minimal corrective action — don't rewrite the function]

**QUESTION: [short title]**
File: path:line
[what you could not verify, and what would settle it]

End the file with "Checked and clear": what you examined and cleared, and why.
Name what you deliberately did not report, so another pass does not re-raise it.

Return "No findings" if the diff clears your question. Do not manufacture
findings to appear thorough. Report only on your question. Each problem has
one owner:
  bugs         behaviour that is wrong
  removed      an invariant a deleted line enforced that nothing re-establishes
  tests        the tests in the diff, and the test the bug fix owes
  risk         security, and cost at scale
  conventions  names, comments, layering, style the linter does not check
  lean         code that should not exist, or already exists elsewhere
  intent       what should have changed and didn't; the issue; other repos
```

## Agent rows

Each row has three parts: **Question** (goes in the QUESTION slot verbatim), **Reach**,
and **Kind** (the block label).

### 1 · bugs — `BUG:`

**Question.** Work these angles in order, each over the whole diff, in this context:
(a) Line by line: read every hunk, then the enclosing function of each hunk. For every
line ask what input, state, timing or platform makes it wrong — inverted or incomplete
condition, off-by-one, nil/empty/zero-value deref, falsy-zero treated as missing, error
swallowed or wrapped away, wrong variable after copy-paste, missing cancellation or
context propagation, unescaped regex metacharacters, unbounded reads. (b) Cross-file:
for each changed function grep its callers and check whether the change breaks a call
site — a new precondition, a changed return shape, a new error value, a timing or ordering
dependency; then its callees, in case a parallel change in this diff makes a call unsafe.
(c) Language pitfalls for this diff's language — Go: nil-map write, range-variable
capture, goroutine leak, lock held across a call, `defer` in a loop, shadowed `err`,
non-pointer receiver mutation, slice aliasing; Python: mutable defaults, late-binding
closures; JS: `==`, falsy-zero; SQL built from strings; timezone and float equality.
(d) Wrappers: a new or modified cache, proxy, decorator or adapter must route every
method to the wrapped instance, not back through a registry, session or global, and must
forward every method callers use. (e) Shared state: does every consumer of changed shared
state — a struct field, a KV key, a config value, a cached value — see the change, and does
any reader assume the old shape? (f) Per request: what does each new call cost per
request, and what does each new log line do on its second tick? (g) Unhappy paths and
trust boundaries: trace what happens when each call fails, times out or returns empty;
name the implicit assumptions about inputs that nothing enforces, especially where trust
transfers between components. (h) Siblings: does each new endpoint, handler or command
check what its closest sibling checks (auth, validation, limits, auditing)?

**Reach.** The enclosing function of every hunk; every caller and callee of a changed
function; every reader of changed state; the closest sibling endpoint or operation;
error paths.

### 2 · removed — `BUG:`

**Question.** For every line the diff deletes or replaces, name the invariant or
behaviour it enforced — a guard, a validation, an error path, a lock, a default, a test
case — then search the new code for where that invariant is re-established. If you cannot
find it, that is a finding: a removed guard, a dropped error path, a narrowed validation, a
deleted test that was covering a real case, moved or extracted code that lost an anchor or
a bound. Also: a config default flipped, a lock scope shrunk, a predicate that gained a
side effect.

**Reach.** The new code for each deletion; neighbouring guards; the tests that covered the
deleted behaviour.

### 3 · tests — `BUG:` for a test that proves nothing, `MISSING:` for a test the diff owes

**Question.** For each test in the diff: which bug in the code under test would make it
fail? A test that passes against a stubbed or inverted implementation proves nothing. Does
it assert only what the code under test owns, and only what no other test already covers?
Does the diff cover both the **expected** behaviour and the **unwanted** behaviour it
guards against (the rejection, the error, the boundary)? If the change fixes a bug, is
there a regression test that fails on the base and passes on the head — construct it in
your head if not. Then conventions: `require` for fatal assertions, `assert` only for
non-fatal, external `xxx_test` package, table-driven where there are three or more cases,
no setup/teardown asymmetry, no sleeps standing in for synchronisation.

**Reach.** The code under test; neighbouring `*_test.go` files; the base commit for the
regression check.

### 4 · risk — `BUG:` (security) and `RISK:` (cost at scale)

**Question.** Security: authz and authn on every new or changed entry point, compared to
its closest sibling; injection (SQL, shell, path, header, template); secrets or tokens in
code, logs or errors; unsafe deserialization; missing input validation; SSRF and path
traversal. Distinguish detection from prevention: a client-side or post-hoc check on a
state-changing operation fires after the side effect is committed; name the real
enforcement boundary and do not credit a detect-only check with preventing anything.
Performance: for every change on a per-request, per-principal or per-object path, name
the input scale at which it bites — O(#tenants) per request, a full table scan per login,
memory held per principal, unbounded fan-out — and what a cold miss costs. Caching
amortizes cost, it does not erase it: say what the cache holds, how large it can grow and
what evicts it. A `RISK:` block carries `Scale:` (the input size where it hurts) instead
of `Trigger:`. A design note is MEDIUM; a scale realistically reachable in production
raises it.

**Reach.** The enforcement boundary for each entry point; the sibling endpoint; the hot
path up to the request handler; the data model for cardinalities.

### 5 · conventions — `VIOLATION:`

**Question.** Does each comment say something the code cannot, and does each doc comment
state the contract rather than why it was built? Is any comment stale after this change,
or does it reference a PR, ticket or prior behaviour? For every new or renamed type,
function, constructor, file-level variable and config key: propose the best name you can,
then report each one where yours beats the current name — what it does now, no stutter
with its package, no word that says less than the code does. Could a reader tell which
lines are new by style alone? Layering: for each new piece of logic, which layer owns this
kind of work, and is that where it landed? Does an upper layer reach past the layer below
it, or a lower layer learn an upper layer's concepts? Does each piece live in the package
and file where its kind already lives? CLAUDE.md: find every CLAUDE.md or CLAUDE.local.md
that governs a changed file (repo root and ancestor directories) and flag only a violation
where you can quote the exact rule and the exact line that breaks it — no "spirit of the
doc".

**Reach.** The three nearest files to each changed file; the package's `errors.go` and
config validation; the full call chain of each changed function top to bottom; how two or
three sibling operations split the same work across layers; every governing CLAUDE.md.

### 6 · lean — `SIMPLIFY:` and `EXISTS:`

**Question.** Argue that this diff is more complicated than it needs to be. For every new
type, interface, function, file, config key, field, parameter, return value and
goroutine: who uses it today? Where would deleting, inlining, hardcoding, flattening or a
stdlib call leave the code shorter and no less clear? Which near-copies must change
together and should merge? Which function does several unrelated jobs and should split?
Is a special case layered on shared infrastructure where generalising the mechanism would
be the deeper fix? Then existence: does this mechanism already exist — in the tree, in a
lower layer of the same call path, in a sibling service, in the stdlib? Does this
dependency already exist in `go.mod` or the stdlib, and is the added one latest stable?
A diff that touches no dependency has nothing to say about freshness: say so.

**Reach.** Every caller of each new symbol; the code each near-copy duplicates; `go.mod`;
greps of the tree for prior art; the sibling service's equivalent code; config samples and
chart values.

`SIMPLIFY:` blocks argue one side on purpose and use this shape instead of Trigger/Fix:

```
**SIMPLIFY: [short title]**
File: path:line
Severity: HIGH | MEDIUM
Current: [what exists, and who uses it today]
Simpler: [delete | inline | hardcode | flatten | stdlib | merge | split | generalise — one or two lines]
Saves: [lines, files, config keys or types removed]
Costs: [what the simpler form loses; "nothing" is a valid answer]
```

`EXISTS:` blocks name the existing mechanism (`path:line`) in `Evidence:`.

### 7 · intent — `MISSING:` and `CONTRACT:`

**Question.** You get a claims file. Everything in it is a claim to test against the
diff, not context: the PR description, the issue, the issue's parents, the commit
messages. (a) Does the diff do what the issue asked — no more, no less? Name what the
issue asked for that is absent, and what the diff does that the issue did not ask for.
(b) What does this diff imply should also have changed and did not: callers, docs, help
text, config samples, chart values, migrations, feature-flag plumbing, the other variants
of the same contract (another language client, another service)? (c) Does the PR
description still match the diff, and does the diff hold only this change? (d) Work that
is visibly unfinished: TODOs in the diff, debug prints, commented-out code. (e) Code with
no caller: check the parent issues first — groundwork for a later planned issue is the
plan, not a defect; report it as a hand-off note naming that issue. Without such a plan it
is `MISSING:` the caller. (f) Cross-repo: list every shared-boundary change the diff makes
or relies on as a contract surface (API shape, schema, config key, flag, auth rule,
version assumption), name the repo on the other side, what breaks there, and the required
deployment order (`doctrine-lakefs.md`). When unsure whether a contract is shared, say so
rather than assuming it is contained.

**Reach.** `<run>/claims.md` (claims only); callers; docs; help text; config samples;
chart values; the consuming repo if it is checked out beside this one (`../<repo>`), else
say it was not available.

```
**MISSING: [short title]**
File: path:line  (or: no file — this was never written)
Severity: HIGH | MEDIUM
[what isn't there, and what depends on it]
Fix: [write it, or record it as an explicit deferral naming the issue]

**CONTRACT: [short title]**
Surface: API | schema | config | flag | auth | version
Severity: CRITICAL | HIGH | MEDIUM
Producer / consumer: <this repo> → <other repo>
[what changes, what breaks on the other side if deployed out of order]
Order: [what must land first]
```

## Merge prompt

```
Merge these review reports of one diff into a single list. You did not write
the code and have no information about why it exists.

INPUT:  <every report path>  (repo root: <agent repo root>)
        Read code only to decide whether two findings are one problem, or
        whether a finding clears the bar.
TASK:
- One problem, one entry. Findings at the same code that the same fix would
  satisfy become one entry: the clearest title and body, the highest severity,
  and every agent that raised it.
- The bar. An entry stays a finding only if a reviewer would ask for the change
  before approving. Move every other entry to the nits, marked "(demoted)".
- Contradictions. When one agent asks for what another rejects, or clears what
  another flags, write one entry with `disputed` giving both positions.
- Questions stay questions. Never promote a QUESTION block to a finding; the
  verifiers prove or refute them.
- Nothing else leaves. Every finding is in the list, merged into an entry, or
  in the nits.

OUTPUT: write <run>/merged.json, one JSON object, nothing else:
{
  "findings":   [{"mid": "f1", "kind": "BUG|VIOLATION|RISK|MISSING|CONTRACT|SIMPLIFY|EXISTS",
                  "title", "severity": "CRITICAL|HIGH|MEDIUM", "file", "line",
                  "raised_by": ["<agent>", ...], "disputed": "<both positions, or omit>",
                  "fields": [["Evidence", "..."], ["Trigger", "..."], ["Fix", "..."]]}],
  "questions":  [{"mid": "q1", "title", "file", "line", "text", "raised_by": [...]}],
  "fix_together": [{"mids": ["f1", "f3"], "note"}],
  "nits":       [{"file", "line", "text", "agent"}],
  "pre_existing": [{"file", "line", "text"}],
  "checked_clear": ["<one line each>"]
}
`mid` numbers findings f1, f2 … in severity order and questions q1, q2 …. `fields`
keeps the agent's block lines in order, label and text, exactly as written
(Evidence, Trigger, Scale, Doctrine, Current, Simpler, Saves, Costs, Surface,
Producer / consumer, Order, Fix, and the body as "Detail"). `fix_together` lists
entries that touch the same code, so one fix can't delete the site another fix
needs. Reply with only the path, the finding count by severity, the question
count and the nit count.
```

## Prove prompt

One per entry in `<run>/proof/tasks/`. Every behaviour claim (`BUG`, `RISK`, a `MISSING`
test) and every question gets one.

```
Prove or disprove one claim from a code review by running code. You did not
write the code or the review. False claims are common; do not feel pressure
to confirm, or to reject.

CLAIM:    <run>/proof/tasks/<mid>.json
TARGET:   the snapshot <SNAP>; the change under review is checked out at
          <AGENT_ROOT>; the base commit <BASE> is checked out at <run>/base
WORKDIR:  <run>/proof/<mid>/ — every file you create goes here
DOCTRINE: <AGENT_ROOT>/CLAUDE.md, for how this repo builds and runs its tests

Never create, edit or delete a file under <AGENT_ROOT> or <run>/base. To add a
test file or replace a source file in Go, write it in WORKDIR and pass it with
`go test -overlay <WORKDIR>/overlay.json`. In any other language, copy what you
need into WORKDIR and run it there.

Method:
1. Write the smallest test that fails on the change under review if the claim
   is true: it drives the trigger the claim names and asserts the correct
   behaviour.
   - A claim that a test proves nothing: break the code under test through
     the overlay and show that the test still passes.
   - A claim about cost: count calls, queries or allocations as the input
     grows, or benchmark two input sizes.
   - A claim that needs a running server: use the `verify-lakefs` skill when
     it is installed.
2. Run it against <AGENT_ROOT>.
3. When it fails as claimed, run it against <run>/base. Failing there too
   means the problem was already there.
Fix what stops the test from building before you give up on it.

Verdict, exactly one:
  PROVEN        the test fails on the change the way the claim says, and
                passes on the base or cannot run there (say which)
  REFUTED       the test passes on the change, or the code rules the
                trigger out; quote the line that does
  PRE_EXISTING  the test fails on the base too
  THEORETICAL   no local test can reach the trigger: production data, an
                outside service, timing that cannot be forced. Name what is
                out of reach. A build you could not fix counts only with the
                error quoted.
For a question that you prove, also give the kind (BUG or RISK) and the
severity: CRITICAL data loss, a security hole or an outage; HIGH wrong
behaviour a user or operator will hit; MEDIUM a reviewer blocks on it.

OUTPUT: write <WORKDIR>/result.json, one JSON object:
{"mid", "verdict", "kind": "<questions only>", "severity": "<questions only>",
 "file", "line": <re-derived with grep -n; no anchor past the file's end>,
 "proof": {"method": "unit|overlay|mutation|count|server|none",
           "files": ["<WORKDIR paths>"], "command": "<what you ran>",
           "result": "<the decisive output lines, at most 20>"},
 "reason": "<one or two sentences>"}
Reply with only the path and the verdict.
```

## Static check prompt

One agent. It checks the findings that rest on quoted text (`VIOLATION`, `SIMPLIFY`,
`EXISTS`, `CONTRACT`, a `MISSING` that is not a test) and accounts for the previous
round.

```
Check review findings that rest on quoted text, not on behaviour, and account
for the previous round. You did not write the code or the review.

INPUT:  <run>/merged.json; the entries to check are the mids in
        <run>/proof/static.json. The snapshot <SNAP> (repo root: <AGENT_ROOT>,
        base commit: <BASE>).
        <re-review only: the previous round's findings, <run>/prev.json; the
        user's waived ids: <ids or "none">>

For each listed entry:
  1. Is it real? The quoted line is in the file, and the quoted rule says what
     the entry claims.
  2. Did this diff introduce it? `git grep` the construct on the base commit.
  3. Is it already handled? The rule's own exceptions, the three nearest files
     doing the same, a later line in the diff.
Verdict: CONFIRMED, REFUTED (quote what disproves it) or PRE_EXISTING.
Re-derive each `file:line` with `grep -n`.

Re-review only. For every finding in prev.json, state its fate against the
current code, not a commit message: `fixed` (how), `not_fixed` (where it still
is), or `waived` (only when its id is on the waived list). When an entry in
merged.json, finding or question, is the same problem as a prior finding,
map its mid to the prior id.

OUTPUT: write <run>/static.json, one JSON object:
{"static": [{"mid", "verdict", "checked": "<what you looked at>",
             "reason": "<for REFUTED or PRE_EXISTING>", "file", "line"}],
 "prior":  [{"id", "fate": "fixed|not_fixed|waived", "note"}],
 "carry":  {"<mid>": "<prior id>"}}
Reply with only the path and the count of confirmed, refuted and pre-existing.
```
