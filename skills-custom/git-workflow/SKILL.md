---
name: git-workflow
description: Use when creating or naming a git branch, writing or amending a commit message, or drafting or opening a pull request (including with the gh CLI). Also when choosing a commit format, deciding how much to write, or linking a commit to an issue.
---

# Git Workflow

The goal of every commit and pull request is one thing: a message that
helps the people who read it and is appreciated later. Format matters far
less than that. This skill covers how to write those messages, how to name
branches, and how to open PRs with the `gh` CLI.

## Branches

Kebab-case, lowercase, descriptive but not verbose:
`lakectl-upload-add-missing-progress-bar`,
`aws-login-fix-region-detection`.

No prefixes. Not `udi/`, not `fix/`, not `feature/`. The name says what
the work is; a category in front of it adds nothing.

Keep it short. It names the work, not the whole change.

## What makes a change message useful

These principles apply to both commit messages and PR descriptions. The
sections below build on them.

### Know who reads it

A change message has two readers, in this order:

1. The reviewer, right now. The message is the first thing they see, and a
   clear one lets them catch problems before the code ships.
2. Future maintainers, later. Someone running `git blame` on a confusing
   line wants to know why it exists.

A direct consequence: anything you would explain in a Slack message, an
email, or by leaning over the reviewer's desk belongs in the message
instead. Write it once, where everyone who needs it will find it.

### Keep it proportionate

The reader's time is the scarce resource. Match the length of the message
to the size and risk of the change.

- A trivial change gets a one-line subject and no body.
- A change with non-obvious motivation, a subtle bug, a breaking effect,
  or a lesson worth keeping gets a body.

Never pad a small change with a long message. An over-explained typo fix
trains people to stop reading commit messages.

### State the effect in the subject

The subject line says what the change does for the reader, not how it was
built. The diff already shows the mechanism.

```
Bad:  add a mutex to guard the database handle
Good: prevent database corruption during simultaneous sign-ups
```

### Put the most important thing first

Order the body so a reader can stop as soon as they have what they need.
The core reason and effect come first. Background, alternatives, stories,
and asides come last, under their own headings if the message is long.

## Commit messages

A commit records one logical change. Its message explains that change to a
reviewer today and a maintainer years from now.

### Format

Match the format the repository already uses. Read a page of `git log`
first, and check for a `commitlint` config or a `CONTRIBUTING` file. The
repository's own convention always wins.

When the repository has no established style, the preferred default is
conventional commits: `<type>(<scope>): <description>`, where type is one
of `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`,
`build`, or `style`. It is a good default, not a requirement, so:

- The scope carries most of the value. It is the area of code the change
  touches, taken from the file paths in the diff (`auth`, `gateway`,
  `auth/session`). Keep it even when you drop the type.
- The type is often redundant, since the description usually makes it
  obvious. When it adds nothing, a plain scope prefix in the style of
  Linux, Git, and Go is just as good: `gateway: fix signature mismatch`.
- Some changes need neither a type nor a scope. A plain descriptive
  subject is a fine message.

Whatever the form, the words after any prefix carry the value. Do not put a
ticket number in the scope; that replaces the one useful field with a
useless one. Ticket references go at the end of the body (see below).

### Subject line

- Use the imperative mood: "add", not "added" or "adds". It should complete
  the sentence "if applied, this commit will ...".
- Keep it under 50 characters, 60 at the most. It shows up truncated in
  `git log --oneline`, `git rebase -i`, `git shortlog`, and GitHub.
- No trailing period.

### Body: what, why, and how

Write the body when the change earns one. Answer the questions the diff
does not already answer, and skip the rest:

1. Why is the change necessary? The context and the problem it solves.
2. How does it work? Contrast the old behavior with the new. Write
   "profiles with null fields used to crash; now the code guards before
   access", not "added a null check".
3. What side effects does it have? If you find yourself listing several
   unrelated effects, the commit is doing too much. Split it.

Formatting the body:

- Leave a blank line after the subject. Tools such as `git rebase` rely on
  it.
- Wrap lines at about 72 characters. `git log` does not reflow text.
- Write prose. Use a bulleted list only when the content is a genuine
  enumeration.
- For a long, complex message, use short headings (Background, Motivation,
  Alternative 1, and so on) so the reader can find the part they need.

### Include when the change warrants it

Reach for these only when they apply. They are not a checklist to fill on
every commit.

- Motivation and constraints. Why this solution, and what ruled out the
  obvious one.
- A summary of a referenced bug. Do not write `Fixes #1234` and leave the
  reader to read the whole ticket. Pull the relevant details into the body.
- Breaking changes. State what breaks and what clients must do. Flag it
  with a `BREAKING CHANGE:` trailer.
- A justification for a new dependency. Dependencies are a long-term cost;
  say why this one is worth it and how you chose it.
- Testing instructions, when automated tests do not cover the change.
- Testing limitations, when you could not test a relevant scenario. It
  tells the reviewer where the risk is.
- What you learned, when the change taught you something non-obvious that
  the next person would otherwise rediscover.
- Alternatives you considered and rejected, when the reason does not fit in
  a code comment.
- Searchable text. If the change relates to a specific error message, put
  the exact text in the body so `git log --grep` finds it later.

### Leave out

- Facts the diff makes obvious: which files changed, which APIs you called,
  whether the change is large or small.
- Critical maintenance rules. If a future edit could break something
  silently, that rule belongs in the code as a comment and, where possible,
  an automated check. A maintainer editing the file may never read the
  commit that explains it.
- Review-only chatter ("does this look right?"). That belongs in a PR
  comment, not in permanent history.
- Preview URLs and build artifacts. Let tooling surface those. They go
  stale and add noise.

### References

Link the issue at the end of the body. `Closes #123` auto-closes it on
merge; `Refs #123` references it without closing. Prefer a full URL when
the tracker is external or ambiguous:
`Refs https://github.com/org/repo/issues/482`. Omit it entirely when
there is nothing to link.

### Other rules

- Breaking changes: add `!` after the type or scope and a `BREAKING CHANGE:`
  trailer.
- Do not write real messages with `git commit -m`. It pushes you to cram
  history into one line, and the body does not survive it well.
  Compose in the editor.
- No AI co-author trailers. Do not add `Co-authored-by` for AI assistants
  (Copilot, Claude, Amp, and the like). Credit only human contributors.

### Workflow

1. Run `git diff` (staged and unstaged) to see exactly what changed.
2. Read a page of `git log` to match the repository's format.
3. Derive the scope from the changed file paths.
4. Find any referenced issue or PR, from the diff or the branch name.
5. Draft the message. Answer only the body questions the diff leaves open.
6. Commit. Do not push; leave that to the user.

### Examples

A trivial change, obvious from the diff, needs no body:

```
docs: fix broken link to the install guide
```

A bug fix where the body earns its place. Note the old-versus-new
contrast and the issue link:

```
fix(api): reject profile updates with null required fields

Profiles created before the schema migration have null bio and location
fields. The renderer read them directly and crashed with a null
dereference on those accounts.

Guard the access so missing fields render as empty instead of throwing.

Closes #482
```

A refactor with no external reference:

```
refactor(database): extract shared query patterns

The list, get, and count handlers each rebuilt the same filter and
pagination clauses inline, and the copies had already drifted apart once.
Pull the shared construction into one query builder so the three paths
share a single definition.
```

## Pull requests

A PR describes a whole feature or fix, one step up in scope from a commit.
The principles in "What makes a change message useful" apply unchanged. The
difference is granularity and the merge mechanics.

In a squash-merge repository (lakeFS is one), the PR description becomes the
body of the squashed commit on the main branch. Write the PR description to
the same bar as a commit message, because that is what it becomes.

A PR description answers three questions:

- What changed?
- Why is it needed?
- How was it tested?

The PR title becomes a changelog entry and the squashed commit subject, so
write it for the effect on users, not the implementation. "Fix crash when
uploading large files" beats "Fix null pointer in FileHandler".

### Before writing

Gather context first:

1. Check for a template: `.github/pull_request_template.md` or
   `.github/PULL_REQUEST_TEMPLATE/`. If one exists, follow its structure.
2. Read the diff: `git diff <base>..HEAD`.
3. Read the commits: `git log --oneline <base>..HEAD`.
4. Check for related issues: `gh issue list --search "<keywords>"`.
5. Push the branch: `git push -u origin <branch>`.

### Create with gh

```bash
gh pr create --title "feat(auth): add login rate limiting" --body "$(cat <<'EOF'
## Summary
Add rate limiting to the login endpoint to blunt brute-force attempts.

## Changes
Adds sliding-window rate limiting to /auth/login, backed by Redis, with
RATE_LIMIT_* configuration variables.

## Testing
Unit tests cover the window logic. Integration tests confirm the endpoint
returns 429 once the limit is hit.
EOF
)"
```

### Labels, assignees, reviewers

```bash
gh pr edit --add-label "bug,priority:high"
gh pr edit --add-assignee @me
gh pr edit --add-reviewer username1,username2
```

### Gather issue context

```bash
gh issue view 123            # issue details
gh issue view 123 --comments # full discussion
gh issue list --search "auth rate limit"
```

### Amend a PR description

```bash
gh pr view                          # current title, body, diff stats
gh pr diff                          # full diff from GitHub
gh pr edit --title "..." --body "..."
gh pr view --json body -q .body     # read current body before editing
```

### lakeFS conventions

Add the `include-changelog` or `exclude-changelog` label. Add
`minor-change` for small PRs with no linked issue. Assign the PR to
yourself.

### PR focus by type

| Type     | Focus on                                      |
|----------|-----------------------------------------------|
| Feature  | User value, docs updates, rollout             |
| Bug fix  | Root cause, repro steps, regression test      |
| Refactor | What stays the same, what improves, the risk  |
| Docs     | Accuracy, working examples                    |

## Anti-patterns

- Buried lede: the reason for the change sits under three paragraphs of
  background. Put it first.
- Wall of text: a long message with no headings. Add structure.
- Mechanical toil: treating the message as a form to fill rather than a
  note to a colleague. If it reads like a chore, cut it down.
- Monster PR: too many unrelated changes. Split it.
- Mystery PR: no description. Add the context.
- Rushed PR: tests skipped. Add them before review.
