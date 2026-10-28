# Treeverse / lakeFS doctrine

Handed to agents through the Doctrine slot, after the repo's own `CLAUDE.md` and style
guide, which win on conflict. Everything here is a rule an agent could not measure from
the tree; everything it *can* measure, it must measure — count the convention in the repo
under review rather than quoting a remembered baseline, because lakeFS, lakeFS-Enterprise
and cloud-controlplane differ.

## Go

- **Assertions:** `require` for anything the rest of the test depends on, `assert` only
  for non-fatal checks. Legacy `t.Errorf`/`t.Fatalf` in old files is volume, not precedent.
- **Test package:** external `xxx_test` (`package graveler_test`). A `docs/go-style-guide.md`
  line saying same-package for unit tests is stale; follow the tree. `export_test.go` in
  the package's own name is the standard idiom, not a violation.
- **Tables:** table-driven by default; verify core behaviour clearly rather than one test
  per error path.
- **Errors:** `errors.Is`/`errors.As`, never message comparison. Needing a message
  comparison means the package owes the caller a distinct error value. Sentinel errors
  live in the package's `errors.go` where one exists.
- **Comments:** timeless. No PR, ticket or prior-behaviour references; why a change was
  made belongs in the commit message. A doc comment states the contract.
- **Context:** `ctx` first, propagated, never stored in a struct; respect cancellation on
  loops and I/O.

## Layers

In lakeFS core, each layer calls only the one below it; a lower layer never learns an
upper layer's concepts:

| Layer | Package | Owns |
|---|---|---|
| API controller | `pkg/api` | authorization, request parsing, response shaping |
| catalog | `pkg/catalog` | maps API concepts onto graveler; entry and metadata semantics |
| graveler | `pkg/graveler` | versioning — refs, commits, staging, merge |
| kv / block | `pkg/kv`, `pkg/block` | persistence |

lakeFS-Enterprise services and cloud-controlplane have their own stacks (handler →
service → store is common); measure them from two or three sibling operations in the same
package before ruling.

## Cross-repo

Deployment order, which is also merge order: **lakeFS (OSS) → lakeFS-Enterprise →
cloud-controlplane.** Enterprise builds on OSS; the control plane provisions and drives
Enterprise. A change on a shared boundary names the other repo, what breaks there, and
which side lands first.

Contract surface — the shared-boundary facts every intent report carries, omitting empty
lines:

```
<repo>@<target> — role: producer | consumer | both
API:      changed/added signatures, request/response shapes, status codes
Schema:   wire/DB schema, migrations
Config:   config keys, defaults, chart values
Flags:    feature flags, gates
Auth:     authn/authz, RBAC, permissions
Version:  version assumptions, min-compatible versions
```

**Variant parity:** when one contract is implemented across variants (language clients,
SDKs, services), enumerate every variant; one that diverges or is unimplemented is a
finding even when deliberately deferred — say so and name the deferral.

**Planned groundwork:** an issue under a milestone or epic may land code whose caller
comes in a later issue of the same plan. The intent agent reads the parent issues before
calling code unwired; with the plan in hand it is a hand-off note naming the later issue,
not a defect.

## lakeFS-Enterprise

- **CHANGELOG:** PRs never edit `CHANGELOG.md`; the release PR builds it from labels. A
  user-facing change carries the `include-changelog` label, an internal one
  `exclude-changelog`. A diff that touches the file is a `VIOLATION:`; a user-facing diff
  with no mention of the label is a `MISSING:` for the intent agent.
- **Lint:** `make lint` runs `golangci-lint` with `unused` on; CI enforces it. An unused
  helper is a finding the compiler will not catch.
- **Path params:** a `+` in a path parameter arrives as a space after routing; code that
  compares raw identifiers against path params must account for it.

## Judgement rules

- **Verify before you assert, at every severity.** A finding that rests on a library
  method, a runtime detail or a pinned version is substantiated by running it or reading
  the vendored source at the pinned version, never from memory. If it cannot be verified
  it is a `QUESTION:` block, with no severity.
- **Check the base first.** If the same construct exists in the pre-change tree it is not
  a defect this change introduces, and usually not a defect at all.
- **Two altitudes.** Architecture and contract, and the line level inside every changed
  symbol — constructors, error types, status propagation, argument order, return values,
  off-by-one. Deep analysis is no excuse for missing a local defect.
- **Framework overrides are complete or wrong.** A wrapper over a library method is
  checked against every mode that method supports — streaming vs. buffered, sync vs.
  async, error vs. success — against the pinned version in the lockfile.
- **Detection is not prevention.** A check that runs after a state change is committed
  surfaces the problem; it does not prevent it. Name the real enforcement boundary.
- **Tests are evidence of intent.** Before calling code dead or redundant, prove what
  breaks if it were removed — against the library's documented behaviour and the tests
  in this same diff.
- **Anchors come from the file.** Every `path:line` is re-derived with `grep -n` on the
  head; patch positions and numbered diff views lie.
