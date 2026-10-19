#!/usr/bin/env bash
# dangerous-local-guard.sh — Claude Code PreToolUse hook for the Bash tool.
#
# Environment-INDEPENDENT companion to prod-mutation-guard.sh. That guard gates
# mutations against PRODUCTION; this one gates commands that are destructive to
# the local machine or repo regardless of environment:
#   DENY  — catastrophic & irreversible: wiping / or $HOME, mkfs, dd to a device,
#           reboot/shutdown/poweroff/halt.
#   ASK   — destructive & hard to recover: git clean -f* (permanently deletes
#           untracked files), bare `git push --force`/-f, kill -1, pkill -9.
# `git push --force-with-lease` is intentionally allowed (safe, and central to the
# stacked-PR workflow); only a BARE --force/-f prompts. `git reset --hard` and
# `git stash drop/clear` are deliberately NOT gated — they're routine and their
# state is recoverable from the reflog.
#
# Fails OPEN: any error, missing jq, or empty command exits 0 and proceeds.

set -uo pipefail

# ============================ CONFIG — EDIT THIS ==============================
# Catastrophic, irreversible operations -> hard DENY.
CATASTROPHIC_LOCAL_RE='((^|[[:space:]])(sudo[[:space:]]+)?(reboot|shutdown|poweroff|halt)([[:space:]]|$)|(^|[[:space:]])mkfs([[:space:].]|$)|(^|[[:space:]])dd[[:space:]]+.*of=/dev/|(^|[[:space:]])(sudo[[:space:]]+)?rm[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(/|/\*|~|~/|\$HOME|\$HOME/|\$\{HOME\}/?)([[:space:]]|$))'

# Destructive but recoverable operations -> ASK. Force-push is handled separately
# so --force-with-lease can be exempted.
RISKY_LOCAL_RE='((^|[[:space:]])git[[:space:]].*clean[[:space:]]+-[a-zA-Z]*f|(^|[[:space:]])kill[[:space:]]+(-9[[:space:]]+)?-1([[:space:]]|$)|(^|[[:space:]])pkill[[:space:]]+-9([[:space:]]|$))'

AUDIT_LOG="${DANGEROUS_GUARD_AUDIT_LOG:-$HOME/.claude/dangerous-audit.log}"
# ==============================================================================

command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat 2>/dev/null)" || exit 0

tool="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
[ -n "$tool" ] && [ "$tool" != "Bash" ] && exit 0

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -z "$CMD" ] && exit 0

audit() { # $1=decision
  local ts oneline
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" || ts='?'
  oneline="$(printf '%s' "$CMD" | tr '\n\t' '  ')"
  { printf '%s\t%s\t%s\n' "$ts" "$1" "$oneline" >> "$AUDIT_LOG"; } 2>/dev/null || true
}

# Scan each &&/||/;/| and newline segment independently, so a flag in one command
# (e.g. `gh workflow run ... -f field=val`) is never associated with a `git push`
# in a different command of the same block.
catastrophic_seg=""; risky_seg=""; forcepush_seg=""
while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"   # ltrim
  seg="${seg%"${seg##*[![:space:]]}"}"   # rtrim
  [ -z "$seg" ] && continue
  [ -z "$catastrophic_seg" ] && printf '%s' "$seg" | grep -iqE "$CATASTROPHIC_LOCAL_RE" && catastrophic_seg="$seg"
  [ -z "$risky_seg" ] && printf '%s' "$seg" | grep -iqE "$RISKY_LOCAL_RE" && risky_seg="$seg"
  # bare `git push --force`/-f in THIS segment (but not --force-with-lease)
  if [ -z "$forcepush_seg" ] \
     && printf '%s' "$seg" | grep -iqE '(^|[[:space:]])git[[:space:]].*push' \
     && printf '%s' "$seg" | grep -iqE '(--force([[:space:]]|$)|(^|[[:space:]])-f([[:space:]]|$))' \
     && ! printf '%s' "$seg" | grep -iqE 'force-with-lease'; then
    forcepush_seg="$seg"
  fi
done < <(printf '%s\n' "$CMD" | tr ';|&' '\n')

decision=""; culprit=""; why=""
if [ -n "$catastrophic_seg" ]; then
  decision="deny"; culprit="$catastrophic_seg"
  why="a CATASTROPHIC, irreversible operation (wipes a filesystem/home/root, formats a disk, or halts the machine)"
elif [ -n "$risky_seg" ] || [ -n "$forcepush_seg" ]; then
  decision="ask"
  if [ -n "$forcepush_seg" ] && [ -z "$risky_seg" ]; then
    culprit="$forcepush_seg"; why="a bare 'git push --force' that can clobber remote history (prefer --force-with-lease)"
  else
    culprit="${risky_seg:-$forcepush_seg}"; why="destructive to your local repo/processes (discards work or kills processes)"
  fi
fi

[ -z "$decision" ] && exit 0   # nothing dangerous -> defer to normal flow

show="$culprit"; [ "${#show}" -gt 120 ] && show="${show:0:117}..."
if [ "$decision" = "deny" ]; then
  reason="⛔ BLOCKED: «${show}» is ${why}. If truly intended, run it manually outside Claude."
else
  reason="⚠ Gated command: «${show}» — ${why}. Confirm only if intended."
fi

audit "$decision"
jq -n --arg d "$decision" --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: $d,
    permissionDecisionReason: $r
  }
}'
exit 0
