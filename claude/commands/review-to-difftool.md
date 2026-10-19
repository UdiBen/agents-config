---
description: Run a code review and post the findings into difftool as inline agent comments
argument-hint: <PR number | branch | diff range | difftool review ref> [deep]
allowed-tools: Bash(difftool:*), Bash(gh:*), Bash(git:*)
---
Review the target in `$ARGUMENTS` and wire the findings into a difftool review so I can
triage them in the browser. Do NOT post anything to GitHub — difftool agent comments
stay local until I promote them myself.

This is glue: a reviewer skill produces findings, difftool is the sink. difftool also
ships this wiring as a manual path (`difftool skill` loads the review skill; the comment
sidebar has a copy-prompt button) — this command just automates it and runs the reviewer first.

## 1. Ensure a difftool review exists for the target
- `difftool review list --json` first — if a review already covers `$ARGUMENTS`, reuse its ref.
- Otherwise create one and capture the ref it prints:
  - a number  -> `difftool pr $ARGUMENTS --no-open`
  - a range   -> `difftool diff $ARGUMENTS --no-open`
  - a branch  -> `difftool diff main...$ARGUMENTS --no-open`
- Use difftool as the source of truth for scope: `difftool review get --review <ref> --stat`
  tells you exactly which files are in the diff.

## 2. Produce the findings
- Pick the reviewer from `$ARGUMENTS`: if it ends with `deep` or `adversarial`, invoke the
  `adversarial-code-reviewer` skill; otherwise invoke the `code-review` skill (the default,
  faster, effort-tiered). Either way the target is the same PR/branch/range.
- Verify every candidate against the real source before keeping it — refute anything you
  can't confirm from the code.
- Findings that depend on code OUTSIDE the diff (error mappings, janitors, callers) are valid
  but flag them as such; anchor them to the closest changed line that is in the review.

## 3. Wire findings into difftool (the whole point)
- Read the board first so you don't duplicate: `difftool review comment list --review <ref> --kind human --context`.
- Build ONE JSON batch: `{"comments":[{filePath, match, type, body, author}]}`.
  - `filePath` must match `review get` exactly; anchor by `match` (distinctive changed-line
    text) — never hand-count line numbers.
  - `type`: `issue` (bug/blocking) · `suggestion` (improvement) · `note` (nit/question).
  - `author`: `"code-review (claude)"` so I can filter agent findings in the browser.
  - Write the batch to a file to avoid shell escaping.
- Validate, then apply:
  - `difftool review comment apply --review <ref> --input <file> --dry-run`  (must report 0 problems)
  - `difftool review comment apply --review <ref> --input <file> -q`
- `difftool review goto --review <ref> --comment <first-id>` to scroll my browser to the top finding.

## 4. Report
List the findings ranked most-severe first, the review URL, and remind me the comments are
local — I promote the ones I agree with from the browser and submit them as my own PR review.
