# Doctrine Reference

Doctrine is loaded, not remembered. The authoritative sources are in the repos;
these files only index them and record the deltas that are nowhere written down.

## Load order

1. **Nearest `CLAUDE.md`** to the files under review. A directory-level file
   overrides the root one for code in that directory.
2. **Repo style guide**, where one exists.
3. **The files here**, for what the above get wrong or leave unsaid.
4. **The surrounding code.** When 1-3 are silent, the convention is whatever
   the three nearest files already do.

## Where doctrine lives

| Repo | Root doctrine | Style guide | Also |
|---|---|---|---|
| `lakeFS-Enterprise` | `CLAUDE.md` | `docs/go-style-guide.md` | `webui/CLAUDE.md` for the React tree |
| `lakeFS` | `CLAUDE.md` | — | OSS code is inlined into lakeFS-Enterprise; the Enterprise guide applies |
| `cloud-controlplane` | `CLAUDE.md` | — | Go services under `service/pkg/`; Terraform under `tf/` |
| `charts`, `everest-lakefs-csi-driver`, `spark-client` | — | — | Surrounding code only |

## Files here

- [`go.md`](go.md) — Go doctrine deltas, and what the tree actually does.

## When a source contradicts the tree

Say so in the finding. Cite both: what the document requires, and what the
majority of the tree does. A stale style guide is itself a finding — but a
lower-severity one than the code that follows it.
