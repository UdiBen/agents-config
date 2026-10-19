#!/bin/bash
# PreToolUse on Bash: refuse a PR-authoring command until the git-workflow skill has been
# loaded this session, so descriptions are written to its rules rather than improvised.
#
# Fails open: any unexpected condition exits 0 and the command proceeds.
# Never gates a command the user typed themselves.

payload=$(cat 2>/dev/null) || exit 0
command -v jq > /dev/null 2>&1 || exit 0

cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

# A command the user typed is theirs to run.  Claude Code marks these; when the marker is
# absent the payload is indistinguishable from an agent call, so the gate applies.
for field in '.user_initiated' '.tool_input.user_initiated' '.source' '.invocation_source'; do
  v=$(printf '%s' "$payload" | jq -r "$field // empty" 2>/dev/null)
  case "$v" in
    true|user|User|USER|input_box|slash_command) exit 0 ;;
  esac
done

# Only the two commands that author a PR title or description.  Anchored to the start of a
# shell segment so a command that merely mentions the string - a grep, an echo - is not gated.
seg_start='(^|[;&|(]|\$\(|`)[[:space:]]*'
authoring=0
printf '%s' "$cmd" | grep -Eq "${seg_start}gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)" && authoring=1
printf '%s' "$cmd" | grep -Eq "${seg_start}gh[[:space:]]+pr[[:space:]]+edit[[:space:]](.*[[:space:]])?(--body|--body-file|--title|-b|-F|-t)([[:space:]=]|$)" && authoring=1
[ "$authoring" -eq 1 ] || exit 0

session=$(printf '%s' "$payload" | jq -r '.session_id // ""' 2>/dev/null) || exit 0
[ -n "$session" ] || exit 0
[ -f "${TMPDIR:-/tmp}/claude-git-workflow-$session" ] && exit 0

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "Invoke the git-workflow skill before writing a PR description or title, then retry. It sets the rules for length, subject lines and attribution."
  }
}' 2>/dev/null || exit 0
exit 0
