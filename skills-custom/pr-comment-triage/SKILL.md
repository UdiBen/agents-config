---
name: pr-comment-triage
description: Use when going over the review comments on a pull request - a batch of reviewer feedback to work through, decide what to fix versus push back on, draft replies for, and track to zero. Triggers on "go over the comments of <PR>", "triage the feedback on #N", or wanting a tracker for outstanding review threads.
---

# PR Comment Triage

Turn a PR's review comments into one tracked list: what each one asks, where the code actually stands, what to do about it, and a reply to paste. The list persists, so the work survives across sessions until every thread is closed out.

## You Never Post to GitHub

Replies are drafted for the user to send. Do not post comments, reply to threads, resolve threads, submit reviews, or edit the PR body — not with `gh`, not with the API, not "to save a step". A `github-post-guard.sh` hook blocks it, and the user asked for it directly.

Drafting a reply is the deliverable. Sending it is theirs.

## Step 1 — Fetch

Resolve the target to `owner/repo` and a number (accept a URL or a bare `#N`; for `#N` alone, use the repo of the working directory).

```bash
~/.claude/skills/pr-comment-triage/fetch-threads.sh <owner/repo> <number> > $SCRATCHPAD/pr<N>-raw.json
```

One JSON document with `threads` (inline review threads, each with its full reply chain), `reviews` (review summary bodies), and `conversation` (top-level comments). Bots are included — a CI or lint bot often carries a real complaint. Each thread carries `resolved`, `outdated`, and `last_author`.

**`last_author == author` means the PR author replied last** — that is the "already responded" signal. `resolved` is the reviewer having closed the thread.

## Step 2 — Ask What to Include

Report the shape before triaging, then ask:

```
PR #6037 · 22 comments from 2 reviewers
  12 awaiting your reply
   5 you already replied to
   3 resolved
   2 from bots
Include the ones you've already answered?
```

Default to the ones awaiting a reply. Include answered threads when the user wants a follow-up pass, which is common once the branch has moved on since they replied.

## Step 3 — Verify Against HEAD

For every comment, read the code it points at **on the current branch** and decide whether it still applies. This is what makes the status column a fact rather than a guess, and it is the step worth the time: on a PR that has been through a round, the largest bucket is usually comments already addressed by a later push that were never replied to.

Fetch the branch first (`gh pr checkout`, or a worktree) so you are reading the code as the PR now stands, not as it was when the comment was written. `outdated: true` is a hint the line moved, not proof the point was addressed.

Record one of: `fixed` · `partial` · `not done` · `n/a`. That becomes the chip next to "Where it stands".

## Step 4 — Assign a Verdict

Four verdicts. One per comment, chosen on what the user has to *do*:

| Verdict | Means | When |
|---|---|---|
| `done` | Already addressed; just reply and tick | The code answers it and you verified that |
| `fix` | A change is needed | The comment is right and the code doesn't do it yet |
| `push` | Disagree, or decline with a reason | The comment is wrong, out of scope, or the cost exceeds the gain |
| `decide` | Needs the user's call | A product, design, or cross-repo choice you cannot make for them |

Be willing to use `push`. A triage where every comment is `fix` is not a triage — it's a to-do list, and it hands the user no judgement. When you push back, the drafted reply must carry the actual reason, not a softened version of it.

Use `decide` honestly: it is for choices that are genuinely the user's, not a way to avoid forming a view. Say which way you lean and why.

## Step 5 — Build the Page

`~/.claude/skills/pr-comment-triage/template.html` is a working page; fill its four placeholders and publish. **Load `artifact-capabilities` before publishing** — the page declares `capabilities: {artifact: {}}` so ticks persist as new versions, with a `localStorage` fallback for read-only viewers.

- `__TITLE__` — `#<N> review comments`
- `__META__` — `{repo, num, heading, sub, note}`. `note` is optional: use it for a standing instruction from the reviewer that governs several threads (*"let's open issues for things we don't handle now"*), which is otherwise buried in one comment and forgotten in the rest.
- `__THREADS__` — the array below
- `__STATE__` — `{"answered": {}}` on a first build; on a re-run, the state read back off the live page

Each thread object:

| Field | Holds |
|---|---|
| `num` | Display number, 1-based; `null` for ones already closed out |
| `id` | GitHub comment id — the tick key, so it must be stable across re-runs |
| `where` | `path:line`, or `conversation` / `review summary (STATE)` |
| `url` | Deep link to the comment |
| `author` | Commenter's login |
| `bot` | `true` to mark it as a bot |
| `verdict` | `done` · `fix` · `push` · `decide` |
| `comment` | The reviewer's text, verbatim |
| `state` | `fixed` · `partial` · `not done` · `n/a` — the chip |
| `status` | Where the code stands, in one or two sentences, from Step 3 |
| `mine` | Replies the user already posted on this thread |
| `warn` | A precondition that must be true before the reply is honest |
| `suggested` | The reply to paste; `null` when none is needed |

### `warn` is the field that earns its keep

It holds anything that would make the drafted reply *false at the moment it is posted*: work committed locally but not pushed, a PR description not yet edited, an issue promised but not opened, a decision not yet made. A reply saying "moved to SendGrid templates" is a lie until the branch carrying that is pushed.

Set it whenever the reply asserts something not yet true, and say what has to happen first.

## Step 6 — Work It Down

Publish, hand over the link, and stay in the conversation. The page is the shared state: the user ticks what they've handled, and on the next turn you read the ticks back — `action: "read"` on the artifact URL, then the `<script id="state">` block — to see what is left.

Re-running against the same PR **updates the same artifact** (pass its `url`) rather than creating a second one. Read it first, carry `state.answered` forward, and keep each thread's `id` stable so a tick survives a re-fetch.

As threads close out, the ones the user has replied to move to `num: null` and drop to `done` — the page shrinks toward the open ones.

## Red Flags — Stop

- You posted, resolved, or replied on GitHub
- You triaged without reading the code the comment points at — the status column is then fiction
- Every comment came out `fix` — you did not form a judgement
- You wrote `suggested` claiming work that is not pushed, with no `warn`
- A re-run created a second artifact and the user's ticks are stranded on the first
- You dropped bot comments wholesale without reading them
