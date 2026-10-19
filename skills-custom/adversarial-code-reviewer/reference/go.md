# Go Doctrine — Deltas

`docs/go-style-guide.md` in lakeFS-Enterprise is the primary source and is not
repeated here. This file records where it is stale, and the conventions the
tree enforces without documenting.

## Where the style guide is stale

**Test package placement.** The guide's Test Organization table (`Unit |
*_test.go same package`) does not match the tree. External `xxx_test` is the
convention in both Go repos:

| Repo | External `xxx_test` |
|---|---|
| lakeFS-Enterprise (`pkg/`, `services/`, `cmd/`) | 308 / 441 |
| cloud-controlplane (`service/pkg/`) | 46 / 77 |

Treat in-package unit tests as a finding, and the guide's line as the stale
side. `export_test.go` declaring the in-package name is the standard
export-test idiom, not a violation.

## Undocumented but enforced

**Assertions.** `require` for fatal, `assert` for non-fatal. Measured:

| Repo | `require` | `assert` | legacy `t.Errorf`/`t.Fatalf` |
|---|---|---|---|
| lakeFS-Enterprise | ~7200 | ~200 | ~3100 |
| cloud-controlplane | ~900 | ~12 | ~610 |

The legacy calls are volume, not precedent. New tests using raw `t.Errorf` are
a finding. Re-measure the repo you are reviewing rather than quoting these —
they drift, and the two repos differ.

**Comment density.** Default is no comment. A comment must say something the
code cannot, and must be short — two lines, three for a doc comment on an
exported symbol. Never comment a struct field; the rationale goes in the
type's doc comment, or the field gets renamed.

**Timelessness.** Comments, CLI descriptions and docs describe the code as it
is. No PR or ticket references, no "previously X, now Y", no "kept for
backwards compat". That context belongs in the commit message. This is in the
root `CLAUDE.md` and is violated constantly.

**Indirection.** The tree inlines. A helper with one caller, an interface with
one implementation, a new file for a single function, or a wrapper that only
forwards are all findings. Extraction is earned at the second caller.

**Invented mechanisms.** Retry, caching, pooling, pagination, ID generation,
config resolution and error wrapping all already exist somewhere in the tree.
A new one needs a named gap in the existing mechanism. "Didn't quite fit"
without the specific gap is a finding. With a named gap, extend the existing
mechanism; a fork of it is a finding.

**Dependencies.** A new dependency for a few lines of code is a finding; small
is the strongest argument against taking it. A new or bumped dependency is on
the latest stable release, or the commit message says why not.

**Config keys.** A value that never varies per deployment is a constant. A new
config key needs a second deployment that sets a different value.

**lakectl command files.** `cmd/lakectl/cmd` is converging on one file per
command group; see the root `CLAUDE.md` for the size caps and the rule against
leaving a group half-consolidated.

## Errors

`errors.Is`, never message comparison. When this project owns the error,
needing a message comparison means the package owes the caller a distinct
error value — propose adding one rather than matching on text.
