#!/usr/bin/env bash
# prod-context-notice.sh — Claude Code UserPromptSubmit hook.
#
# When the active kube context is production, inject a one-line reminder into
# Claude's context for the turn so it stays cautious rather than relying solely
# on the prod-mutation-guard to catch a slip. Fails OPEN (no output) on anything
# unexpected, so it never blocks a prompt.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v kubectl >/dev/null 2>&1 || exit 0

ctx="$( (kubectl config current-context 2>/dev/null) || true )"
[ -n "$ctx" ] || exit 0
# The prod AWS account id comes from ~/.agents/local.env, kept out of git.
[ -f "$HOME/.agents/local.env" ] && . "$HOME/.agents/local.env"
acct="${PROD_AWS_ACCOUNT_ID:-}"
printf '%s' "$ctx" | grep -iqE "(prod${acct:+|$acct})" || exit 0

jq -n --arg c "$ctx" --arg a "${acct:+, account $acct}" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: ("⚠️ Active kube context is PRODUCTION (" + $c + $a + "). Do not run mutating kubectl/helm/aws/lakectl/terraform commands against it without explicit per-action approval.")
  }
}'
