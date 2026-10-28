---
name: review-to-artifact
description: >-
  Publish a branch's blind-review rounds as one shared review page: every round at the
  same link, findings the team can tick resolved so they fold away for everyone, and a
  "still present" flag on ticked findings a later round reports again. Use when asked to
  "publish the review", "share the review", "put the findings on a page", or "review and
  publish". Runs blind-review first when the branch has no round for its current head.
---

# review-to-artifact

Turns the rounds `blind-review` saved for a branch into one rolling Artifact page. The
review itself is `blind-review`'s job; this skill only delivers it.

| File | What it holds |
|---|---|
| `scripts/build_page.py` | Builds the page from every round of the branch |
| `reference/page.html` | The page template |

## Step 1 — Find the rounds

The branch's rounds live in `blind-review`'s history directory:

```bash
SLUG=$(git branch --show-current | tr '/' '-')     # a PR: its head branch name
HIST="$(cd "$(git rev-parse --git-common-dir)" && pwd)/blind-review/$SLUG"
ls "$HIST"/r*.json
```

For a PR from a fork the slug is `<owner>-<head branch>`, as `blind-review` names it.

Run `blind-review` first when there are no rounds, or when the latest round's `head` is
not the branch's current `HEAD` (for a PR, its current head commit). Otherwise publish
what is there.

## Step 2 — Build the page

```bash
python3 -I <skill dir>/scripts/build_page.py --hist "$HIST" --out <scratch dir>/review-page.html
```

## Step 3 — Publish

Follow the Artifact tool's own publishing rules.

- **First publish** (no `$HIST/artifact.url`): publish the page with `icon: "checklist"`,
  `capabilities: {db: {}, user: {}}`, and a one-sentence `description` naming the repo and
  branch. Save the URL: `echo "<url>" > "$HIST/artifact.url"`.
- **Later publishes:** read the artifact at that URL first (`action: "read"`), then publish
  with `url` set to it and no `icon` or `capabilities`, so the page keeps both.

Give the user the link. The page is private until they share it.

## What the page keeps

The `resolved` collection in the page's store is its only shared state: one document per
ticked finding id, `{resolved: true, at}`. It survives every republish. A finding that was
ticked, then reported again by a later round under the same id, is shown unfolded with a
"ticked resolved, still present" mark until someone ticks it again. Viewers who cannot
write the store tick in their own browser only, and the page says so.

The page shows the rounds saved on this machine. A teammate who reviews the same branch
elsewhere publishes their own page.

## No Artifact tool

Say so and stop. The round's Markdown, `$HIST/r<N>.md`, is the result.
