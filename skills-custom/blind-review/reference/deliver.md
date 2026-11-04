# Delivering a round

The user picks the destinations at Step 0: terminal, artifact, difftool, or several. Each
one reads the saved round, `HIST_DIR/r<N>.json`, never `verified.json`. Chat always gets
at least the verdict line, the finding count by severity, and a link for every other
destination.

## Terminal

The full relay, in this order: the verdict line; each finding in the `r<N>.md` form
(number, severity, title, file, who found it, summary, code, repro, verified and how, both
sides of a dispute, verdict and how); the open questions; the refuted entries, one line
each; nits and pre-existing items as counts; the path of `r<N>.md`. The agents' full
write-ups stay in `r<N>.json` for whoever fixes. No praise, and no summary of what the
change does: the author already knows.

## Artifact

One rolling page per branch, showing every round at the same link. The team ticks findings
resolved and they fold away for everyone.

```bash
python3 -I <skill dir>/scripts/build_page.py --hist "$HIST_DIR" --out <run>/review-page.html
```

Then publish, following the Artifact tool's own rules:

- **First publish** (no `$HIST_DIR/artifact.url`): publish the page with
  `icon: "checklist"`, `capabilities: {db: {}, user: {}}`, and a one-sentence
  `description` naming the repo and branch. Save the URL:
  `echo "<url>" > "$HIST_DIR/artifact.url"`.
- **Later publishes:** read the artifact at that URL first (`action: "read"`), then
  publish with `url` set to it and no `icon` or `capabilities`, so the page keeps both.

The page is private until the user shares it. Its only shared state is the `resolved`
collection: one document per ticked finding `key`, `{resolved: true, at}`, which
survives every republish. A finding that was ticked and then reported again by a later
round is shown unfolded with a "ticked resolved, still present" mark. Viewers who cannot
write the store tick in their own browser only, and the page says so. The page shows the
rounds saved on this machine.

No Artifact tool: say so, and give the path of `r<N>.md` instead.

## Difftool

Inline comments on a local difftool review. Nothing reaches GitHub; the user promotes the
comments they agree with from the browser.

1. **Find the review.** `difftool review list --json`; reuse a review that covers the
   target. Otherwise create one and keep the ref it prints: `difftool pr <number>
   --no-open` in PR mode, `difftool diff <BASE>...<HEAD_SHA> --no-open` for a branch.
2. **Retire the last round.** List the board with `difftool review comment list
   --review <ref>`. Resolve every open comment by `blind-review (claude)` with `difftool
   review comment resolve --review <ref> --id <ids>`, so only the current round is open.
   Leave everyone else's comments alone.
3. **Build one batch** at `<run>/difftool.json`, `{"comments": [...]}`, one entry per
   finding and per open question:
   - `filePath`: the entry's `file`, exactly as `difftool review get --review <ref>
     --stat` lists it.
   - `line`: the entry's `line`. The verifier re-derived it with `grep -n`.
   - `type`: `issue` for a CRITICAL or HIGH finding, `suggestion` for a MEDIUM one,
     `note` for a question.
   - `author`: `"blind-review (claude)"`.
   - `body`: the finding's `r<N>.md` block: `#<id> · <severity> · <tag> · <title>`,
     then `summary`, `evidence` as a code span, `repro`, `Verified:`, the `Disputed:`
     for and against lines when present, `Verdict:`, and who found it. Nothing from
     `fields`. A question's body is `#<id> · question · <title>`, its text, and what
     would settle it.
4. **Dry-run, then apply.** `difftool review comment apply --review <ref> --input
   <run>/difftool.json --dry-run` must report 0 problems. An entry whose line is outside
   the diff moves to the nearest changed line of the same file, taken from the hunk
   ranges in `difftool review get --review <ref> --file <path>`, never from a patch. Its
   body then starts with `(at <file>:<line>, outside the diff)`. A file outside the diff
   anchors to the first hunk of the first changed file the same way. Then apply with
   `-q` and keep the ids it prints.
5. **Point the browser.** `difftool review goto --review <ref> --comment <first id>`.

Give the user the review URL, and remind them the comments are local until they promote
them.
