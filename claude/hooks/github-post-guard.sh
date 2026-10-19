#!/bin/bash
# PreToolUse on Bash: never post to GitHub on the user's behalf without an explicit prompt.
# Any command that would create or edit a PR/issue comment, review, review reply, or
# discussion comment is turned into a permission prompt, even under bypassPermissions.
#
# Fails open: any unexpected condition exits 0 and the command proceeds.
# Never gates a command the user typed themselves.

payload=$(cat 2>/dev/null) || exit 0
command -v jq > /dev/null 2>&1 || exit 0

cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

for field in '.user_initiated' '.tool_input.user_initiated' '.source' '.invocation_source'; do
  v=$(printf '%s' "$payload" | jq -r "$field // empty" 2>/dev/null)
  case "$v" in
    true|user|User|USER|input_box|slash_command) exit 0 ;;
  esac
done

hit=""
# Anchored to the start of a shell segment so a grep or echo mentioning the words passes.
seg_start='(^|[;&|(]|\$\(|`)[[:space:]]*'

# gh subcommands whose only purpose is to post: pr/issue comment, pr review, discussion.
if printf '%s' "$cmd" | grep -Eq "${seg_start}gh[[:space:]]+(pr|issue)[[:space:]]+comment([[:space:]]|$)"; then
  hit="gh pr/issue comment"
elif printf '%s' "$cmd" | grep -Eq "${seg_start}gh[[:space:]]+pr[[:space:]]+review([[:space:]]|$)"; then
  hit="gh pr review"
# gh api against a comments/replies/reviews path with a write method or a body.
elif printf '%s' "$cmd" | grep -Eq "${seg_start}gh[[:space:]]+api[[:space:]]" \
  && printf '%s' "$cmd" | grep -Eq '(/comments|/replies|/reviews|/reactions)([/? "'"'"']|$)' \
  && printf '%s' "$cmd" | grep -Eq -- '(-X|--method)[[:space:]=]+(POST|PATCH|PUT|DELETE)|(^|[[:space:]])(-f|-F|--field|--raw-field|--input)([[:space:]=]|$)'; then
  hit="gh api write to a comments/reviews endpoint"
# gh api graphql mutations that post.
elif printf '%s' "$cmd" | grep -Eq "${seg_start}gh[[:space:]]+api[[:space:]]+graphql" \
  && printf '%s' "$cmd" | grep -Eq 'add(Comment|PullRequestReview|PullRequestReviewComment|PullRequestReviewThread|DiscussionComment)|submitPullRequestReview|updateIssueComment|updatePullRequestReviewComment'; then
  hit="gh api graphql posting mutation"
# curl straight at the GitHub API with a body or write method.
elif printf '%s' "$cmd" | grep -Eq 'api\.github\.com/.*(/comments|/replies|/reviews|/reactions)' \
  && printf '%s' "$cmd" | grep -Eq -- '(-X|--request)[[:space:]=]*(POST|PATCH|PUT|DELETE)|(^|[[:space:]])(-d|--data|--data-raw|--data-binary|--json)([[:space:]=]|$)'; then
  hit="curl write to a GitHub comments/reviews endpoint"
fi

[ -n "$hit" ] || exit 0

reason="This command would post to GitHub as the user ($hit). The user has asked never to have comments, reviews, or replies posted on their behalf without explicit, per-action approval. Approve only if the user asked for exactly this post in their own words."
jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: $r
  }
}'
exit 0
