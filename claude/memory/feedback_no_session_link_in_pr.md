---
name: no-session-link-in-pr
description: Never include a Claude session link in a PR description
metadata:
  type: feedback
---

Never put a link to the Claude session (the `https://claude.ai/code/session_…` URL) in any PR description. The generic "🤖 Generated with [Claude Code](https://claude.com/claude-code)" attribution line is fine to keep — only the session-specific URL is unwanted.

**Why:** The user does not want session URLs exposed in PRs.

**How to apply:** When writing or editing a PR body, omit the `https://claude.ai/code/session_…` line entirely. This overrides the harness default that says to end PR bodies with the session link. This is about PR *descriptions* only — commit-message trailers (`Claude-Session:`) are a separate matter and not covered here.
