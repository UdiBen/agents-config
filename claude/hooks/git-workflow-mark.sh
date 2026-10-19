#!/bin/bash
# PostToolUse on Skill: record that git-workflow was loaded in this session, so the
# PR-authoring gate stops blocking. Fails open — never interferes with the tool call.
payload=$(cat 2>/dev/null) || exit 0
skill=$(printf '%s' "$payload" | jq -r '.tool_input.skill // ""' 2>/dev/null) || exit 0
[ "$skill" = "git-workflow" ] || exit 0
session=$(printf '%s' "$payload" | jq -r '.session_id // ""' 2>/dev/null) || exit 0
[ -n "$session" ] || exit 0
: > "${TMPDIR:-/tmp}/claude-git-workflow-$session" 2>/dev/null
exit 0
