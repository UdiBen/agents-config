# Authoring and attachment

Read this reference only when the requested deliverable includes an authoring file, inspection or
validation of an attached walkthrough, attachment, or update. A proposed walkthrough, audit, or
other explicitly read-only content draft does not use this workflow.

Choose the row that matches the complete requested outcome before acting:

| Requested operation | Allowed workflow |
|---|---|
| Create or edit an authoring file without validation | Write the requested local file; do not attach it. |
| Create or edit and validate an authoring file, or validate an existing file | Write it if requested, then run `walkthrough set --dry-run`; never omit `--dry-run`. |
| Inspect or validate what is already attached | Read it with `walkthrough get --json`; do not run `set` or `clear`. Contract reads and non-mutating viewer checks remain available when the requested validation needs them. |
| Attach a new walkthrough or replace/update an existing one | Run the full `set` workflow below. |

Only the final row authorizes a mutating `set`. Validation, inspection, drafting, or creating a local
authoring file never implies permission to replace the attached walkthrough. `clear` and review
comments likewise require explicit authorization.

## New authoring document

When attachment is requested, attach to an existing review. If none exists, start the review that
matches the request with `difftool diff`, `difftool show`, or `difftool pr`; ask only when the source
is ambiguous. For authoring-file-only work, use the supplied review without creating or mutating one.

Start with compact context and, when useful, a disposable scaffold:

```sh
difftool review get --review <ref> --walkthrough-context --compact
difftool walkthrough init --review <ref>
```

Save the scaffold as `walkthrough.json`, then reshape it around the review story. `init` is raw
material, not the intended stop-per-hunk structure. Preserve its read-only `snapshotId` and pass it
to `set --snapshot <id>` so a changed Snapshot rejects the attach.

## Existing attached walkthrough

Read the attached walkthrough with:

```sh
difftool walkthrough get --review <ref> --json
```

If the request is read-only inspection or validation of the attached result, stop after the needed
resolved, contract, and visual checks. Follow the main skill's non-mutating visual workflow when the
request or a selected contract requires it. The remaining reconstruction and replacement
instructions apply only to an explicit update.

Prefer the original authoring file when available. `get` returns the **resolved viewer shape**, not
round-trippable authoring JSON, and there is no partial update command. If the source file is
missing, reconstruct the complete authored document from the resolved tour and current hunk
context. Preserve IDs, order, prose, references, support, and untouched visuals.

Resolved `htmlAssets` and `svgAssets` contain bundled source. Materialize every referenced asset
beside the authoring JSON before `set`, which bundles local files again. `set` replaces the entire
walkthrough atomically; `init` never preserves an existing tour. If outdated anchors or missing
authoring details prevent faithful reconstruction, explain the gap instead of replacing unrelated
content.

Use `--dry-run` when the edit is broad, anchors or assets are uncertain, the Snapshot may be stale,
or previewing the complete replacement reduces meaningful risk. A fresh, narrowly checked edit does
not need a ceremonial dry run.

## Hard authoring limits

Check these validator-enforced constraints before running `set`:

- Chapter `title`: 1–24 characters. Walkthrough `title` and stop `title`: 1–200 characters.
- Chapter `icon`: `bug`, `wrench`, `path`, `flask`, `beaker`, `doc`, or `gear`.
- Stop `importance`: `critical`, `normal`, or `context`.
- IDs: non-empty, at most 200 characters. Chapter IDs must be unique; stop IDs and rendered
  `support:<group-id>` IDs must also be unique. No special slug format is required.

## Attach or replace the complete document

Use this section only when the user explicitly requested attachment, replacement, or update.

```sh
difftool walkthrough set --review <ref> --agent <name> --file walkthrough.json \
  --snapshot <id> --fail-on-outdated
```

`set` validates and resolves the complete document, then atomically replaces the attached
walkthrough. Keep `--fail-on-outdated` unless an explicitly intentional outdated reference belongs
in the requested result. Errors are hard failures. Warnings are structural signals: investigate
them and fix those that reveal a real problem, but do not maximize hunk coverage merely to eliminate
warnings. Before dismissing uncovered hunks as mechanical, inspect their full changes; compact
samples alone are not enough. Reuse evidence already read. Verified mechanical changes may be
omitted or placed in support. A successful `set` does not establish narrative completeness.

Do not refresh a review merely because it is a Workspace review. Refreshing changes the accepted
Snapshot and should happen only when the reviewer wants the review recaptured. Preserve the review's
stored Target; staging matters only when that Target is explicitly `--staged`.

## Reference hunks

Prefer the hunk ID from compact context:

```jsonc
"src/app.ts:h2"
```

Use a content match when a distinctive changed line identifies the intended current hunk more
clearly than an ordinal. Copy the line without its `+` or `-`:

```jsonc
{ "file": "src/app.ts", "match": "const signal = controller.signal" }
{ "file": "src/app.ts", "match": "return res", "side": "new" }
```

Use `all: true` only when every matching hunk belongs in the stop. Slice a large hunk with a content
boundary or tail:

```jsonc
{ "file": "parser.ts", "match": "export function parse(", "until": "export function print(" }
{ "file": "parser.ts", "match": "export function print(", "toEnd": true }
```

Compact context's `outline` suggests useful boundaries. `set` reports ambiguous matches and invalid
combinations.

Notes use the same ID or match forms for a short annotation at an exact line. Keep each note inside
its rendered slice. References re-anchor within the same file while their content stays unique; they
do not follow renames. After the diff changes, inspect the resolved walkthrough again. Re-set only
when anchors are outdated, the explanation no longer matches, or the user requested an edit.
Deleted or ambiguous anchors become `outdated`; they never silently point elsewhere.

## Validate the requested result

For authoring-file validation without attachment, first compare the file's saved `snapshotId` with
the current accepted Snapshot from compact review context. A mismatch is a validation failure unless
the user explicitly asked to revalidate or rebase the file against the current Snapshot. If the file
has no saved Snapshot, disclose that its authoring baseline cannot be checked.

Then resolve the file against the current review with the non-mutating form:

```sh
difftool walkthrough set --review <ref> --agent <name> --file walkthrough.json \
  --fail-on-outdated --dry-run
```

`--dry-run` validates against the current accepted Snapshot and does not enforce `--snapshot`; only
an attaching `set` enforces that option. Do not describe a successful dry run as proof that the saved
Snapshot was current unless you performed the comparison above.

For read-only inspection or validation of what is already attached, read its resolved state with:

```sh
difftool walkthrough get --review <ref> --json
```

Never run `set` or `clear` for this operation. Targeted component-contract reads and the main skill's
viewer workflow are still allowed when needed to validate rendered or interactive behavior; they do
not replace or mutate the attachment.

After an explicitly authorized mutating `set`, read the resolved walkthrough with the same `get`
command. For an update, compare IDs, order, anchors, components, support, and untouched prose with
the baseline. Then return to the main skill's final reviewer and visual-verification checks.
