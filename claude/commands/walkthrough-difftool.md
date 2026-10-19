---
description: Author a narrative walkthrough of a change and attach it to a difftool review
argument-hint: <PR number | branch | diff range | difftool review ref>
allowed-tools: Bash(difftool:*), Bash(gh:*), Bash(git:*)
---
Author a guided **walkthrough** of the change in `$ARGUMENTS` and attach it to a difftool
review, so it renders as a live hunk-based tour in my browser. A walkthrough *explains* the
change stop-by-stop (chapters → stops → hunks); it does NOT flag findings — use
`/review-to-difftool` for findings. Follow the `difftool-walkthrough` skill.

## 1. Ensure a difftool review exists
- `difftool review list --json` first; reuse the ref if one covers `$ARGUMENTS`.
- Otherwise create it: number → `difftool pr $ARGUMENTS --no-open`; range → `difftool diff <range> --no-open`;
  branch → `difftool diff main...<branch> --no-open`. Capture the ref it prints.

## 2. Gather intent
- Pull the goal + the 2-3 key decisions from the PR/MR description (`gh pr view <n>`, or difftool
  attaches it as a design doc), any design doc / PRD, the linked issue, and `git log`.
- Attach a doc to open beside the tour if useful: `difftool review design add --review <ref> --file <doc.md>`.

## 3. Plan the spine (cheapest read first)
- `difftool review get --review <ref> --walkthrough-context --compact` — plan and anchor from this.
  Escalate to `--file <glob> --include-lines` or `--hunk <file>:hN --include-lines` only for lines you must quote.
- Order stops the way you'd explain it to a colleague — by causality and review leverage, NOT file path.
  Open with an overview stop (the problem + approach). Keep it tight: a handful of chapters, ~5-15 stops.

## 4. Author + attach
- Write `walkthrough.json` (chapters/stops; each stop's `hunks` in reading order, anchored by hunk id
  or `match`, never hand-counted lines). `difftool walkthrough init --review <ref>` prints a scaffold.
- Validate then attach (all-or-nothing): 
  `difftool walkthrough set --review <ref> --agent "claude" --file walkthrough.json --fail-on-outdated`
  (add `--dry-run` first to validate only). **Address any `warning:` lines and re-attach** — a good
  walkthrough attaches clean.

## 5. Report
Give the review URL and the spine (chapter/stop titles). Remind me the tour renders live in the browser;
I open it and step through with Prev/Next / Present mode.
