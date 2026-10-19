## Production Safety

**Production is a read-only environment.** When working against production:
- Do NOT make any changes (data, users, authentication, configuration, etc.) without explicit approval for each change
- Read operations and queries are fine
- Any mutating action requires my explicit approval before execution

* To deploy K8S dev environment in the cloud -
   * https://github.com/treeverse/lakeFS-Enterprise/actions/workflows/enterprise-devenv.yaml
   * Run workflow -> branch: main, helm chart branch: master, setup type: oidc-s3

## Knowledge & Diagrams
* When creating knowledge documents, diagrams, or reference material, place them under `~/code/treeverse/knowledge/`

## Memory
* When I ask you to save something to memory ("remember this", "save to memory", "add a memory", or similar), ask me which scope before writing the file: **user/global** (`~/.claude/memory/`, applies in every project) or **project** (`~/.claude/projects/<id>/memory/`, applies only when CWD is that project). Don't guess — default to asking unless I've specified the scope in the same message.

## Communication Style
* Match existing codebase conventions for **filenames, packages, types, interfaces, identifiers, and file organization (inline vs separate)** — check 2-3 neighboring files before introducing new structure, and tell me which convention you're matching.
* Avoid jargon-heavy explanations; lead with plain language and add technical depth only if asked.

## Before Implementing
* For multi-step or design-adjacent requests, propose the approach in 2-5 bullets (files touched, key naming choices, assumptions) and wait for my confirmation before editing files or committing.
* Never commit spec/design/plan files unless I explicitly tell you to commit them.
* Verify root cause before proposing fixes — e.g., check branch distribution and commit context before labeling a test "flaky," and trace actual code paths before pushing back on simpler alternatives.

## Stacked PR Workflow
* When working with stacked PRs (per-PR worktrees typically under `~/code/worktrees`):
  - After any change to a base PR, cascade-rebase all downstream branches and verify builds before pushing.
  - If a rebase appears to drop commits, inspect the reflog and compare commit subjects pre/post rebase — fix the PR directly rather than blaming tooling.
  - Before declaring "done" on any stack work, walk the full stack and report per branch: (1) clean rebase, (2) build passes, (3) HEAD commit subject. Don't say done until all three are green for every branch.
  - Each PR description must include an ASCII diagram listing all PRs in the stack (in order), with a marker indicating which PR the current one is.
* When I ask to "stack" PRs/branches/features, use the `gh-stack` skill — never just chain `--base` flags manually.

## Branch Naming
* Kebab-case, lowercase, descriptive but not verbose (e.g., `lakectl-upload-add-missing-progress-bar`, `aws-login-fix-region-detection`)
* No prefixes (no `udi/`, `fix/`, `feature/`, etc.)

## PR Descriptions
* Keep PR descriptions concise and high-level
* Don't list implementation details like test names or code snippets - those are easier to review in the actual code
* Focus on the "what" and "why", not the "how"

## Code Comments

Default to no comment. Delete any comment that restates the line below it.

* **Hard cap: 2 lines.** A doc comment on an exported symbol may reach 3. Longer means delete it or fix the code — never reformat prose to fit.
* **One fact per line.** No subordinate clauses, no em-dash asides, no "which means", no narrative.
* **Cases go in a list, not a sentence:**
  ```go
  // The returned status decides what Stripe does:
  // 2xx -> done
  // anything else -> retried for up to three days
  ```
* **Never comment a struct field.** Put it in the type's doc comment, or rename the field.
* Comment only what the code cannot show: another system's behaviour, a deliberate ordering, a magic number, a non-obvious refusal.
* Comments describe **current** behaviour only. No history, no "previously X, now Y", no "kept for backwards compat". Why a change was made belongs in the commit message.
* Wrap prose comments at **90 columns**, filling the line before breaking. A list keeps one case per line, however short.
* Use a **single space** after sentence-ending punctuation, never two.

## Personal Scripts (`~/scripts/`)

Scripts are organized into category subdirectories, all in PATH:
`~/scripts/`, `~/scripts/aws/`, `~/scripts/lakefs/`, `~/scripts/common/`

### aws/
| Script | Purpose | Use instead of |
|--------|---------|---------------|
| `aws.login` | Login to AWS via saml2aws + auto TOTP | `saml2aws login -a ...` |
| `aws.secret` | Retrieve AWS secrets interactively | `aws secretsmanager get-secret-value` |
| `kube.connect` | Update kubeconfig for EKS cluster | `aws eks update-kubeconfig` |

### lakefs/
| Script | Purpose | Use instead of |
|--------|---------|---------------|
| `create.api.token` | Generate JWT for control-plane services | manual token creation |
| `restish.prepare` | Set up restish with port-forwarding + tokens for admin & giam | manual port-forward + restish config |
| `lakectl.set` | Switch active lakectl profile | editing ~/.lakectl.yaml |
| `lakectl.cat` | View lakectl config with syntax highlighting | `cat ~/.lakectl.yaml` |

### common/
| Script | Purpose | Use instead of |
|--------|---------|---------------|
| `generate.mfa.token` | Generate JumpCloud TOTP token (from Keychain) | manual authenticator app |
| `add.alias` | Add shell alias to ~/.aliases | editing ~/.aliases manually |

### Key usage patterns
- **AWS login requires eval**: `eval "$(aws.login)"` or use the `aws.login` shell function in .zshrc
- **Typical dev workflow**: `aws.login` → `kube.connect` → `restish.prepare` → `restish admin/giam ...`
- **MFA alias**: `mfa` is aliased to `generate.mfa.token`
# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

## graphify in lakeFS-Enterprise
When the CWD is `~/code/treeverse/lakeFS-Enterprise` and I ask a natural-language question
about the codebase (how something works, what calls what, where a flow lives), query a graph
FIRST — do not start with a grep/read sweep, and do not rebuild or run detect. Treat the
result as a starting map, then read the cited files to confirm.

Pick the graph by domain. Domain graphs live under `~/.graphify/lakefs-ee/<slice>/graphify-out/`
and include tests (so "what tests exercise X" works there); query with
`graphify query "<q>" --graph ~/.graphify/lakefs-ee/<slice>/graphify-out/graph.json`:
- `core` — graveler, catalog, api, gateway, block, kv, actions, distributed, cmd/lakefs, esti
- `auth` — auth, authentication, permissions, license
- `iceberg` — icebergcatalog, icebergsync
- `everest`, `mirroring`, `webui`, `lakectl`
- `services` — arktika, metadatasearch, mdsquery, sparklessgc, repoman, lakefsapi, metadata, stats
Fall back to the root graph (`graphify query "<q>"`, reads `graphify-out/graph.json`) only for
cross-domain questions; it excludes tests, mocks, and generated code. Prefer `--dfs` or
`graphify explain "<Symbol>"` for "how does X work" questions — BFS fans out.

`~/.graphify/lakefs-ee/build_slices.py --list-slices` shows the slice → directory map;
`build_slices.py <slice>` rebuilds one. The root graph auto-refreshes via the repo's
post-commit and post-checkout hooks. `graphify-out/` and `.graphifyignore` are excluded
locally in `.git/info/exclude` — never commit them, and never add graphify entries to the
repo's tracked `CLAUDE.md` or `.gitignore`.
