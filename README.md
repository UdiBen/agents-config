# agents-config

Version-controlled configuration for my AI coding agents, tracked in place from
`~/.agents`. Skills are shared by every agent; agent-specific config lives in its own
folder and is linked into that agent's home. Personal setup, shared as-is.

## Layout

| Path | Purpose |
|------|---------|
| `skills-custom/` | My own skills (tracked) |
| `skills-local/` | My own skills that hold internal or customer data (not tracked, this machine only) |
| `skills/` | What agents load: links to `skills-custom/` and `skills-local/`, plus third-party skills (not tracked) |
| `.skill-lock.json` | Third-party skills installed by [`npx skills`](https://github.com/vercel-labs/skills) |
| `claude/` | Claude Code config: `CLAUDE.md`, `settings.json`, status line, `hooks/`, `commands/`, `memory/` |
| `local.env` | Machine-local values such as AWS account ids, read by the hooks and status line (not tracked) |
| `link.sh` | Creates every link below; safe to re-run |

## Who reads what

| Agent | Skills | Config |
|-------|--------|--------|
| Codex | `~/.agents/skills` (native location) | — |
| Claude Code | `~/.claude/skills` → `~/.agents/skills` | `~/.claude/<file>` → `~/.agents/claude/<file>` |

## Restore on a new machine

```sh
git clone git@github.com:UdiBen/agents-config.git ~/.agents
~/.agents/link.sh
```

Recreate `local.env` with `PROD_AWS_ACCOUNT_ID` and `STAGING_AWS_ACCOUNT_ID`. Without it
the prod guards still catch `prod`-named contexts, but not raw-ARN ones.

Third-party skills are not tracked. Reinstall each entry in `.skill-lock.json` with
`npx skills add <source> -g -s <name>`.

## Notes

- Everything not listed in `.gitignore`'s allowlist stays untracked: session data,
  caches, credentials, and `settings.local.json` all live in `~/.claude`, outside this repo.
- If Claude Code saves `settings.json` by replacing the link with a regular file, re-run
  `link.sh`: it copies the edited file into the repo and restores the link.
- Plugins are declared in `claude/settings.json` and re-installed by Claude Code.
