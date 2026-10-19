#!/usr/bin/env bash
# prod-mutation-guard.sh — Claude Code PreToolUse hook for the Bash tool.
#
# Enforces "production changes need explicit per-action approval"
# at ACTION TIME (memory/preferences alone cannot — the model has to remember).
# When a Bash command targets a production context AND any &&/||/;/| segment of it
# performs a known MUTATING operation, the hook returns "ask" (or hard "deny" for a
# catastrophic, irreversible verb). It flags DETECTED mutations rather than
# requiring every segment to be a recognized read-only command — the latter proved
# too noisy against legitimate read-only work (greps with alternations, for-loops,
# redirects like 2>/dev/null, cd, [ ] tests). Read-only prod queries and every
# non-prod command pass untouched.
#
# Fails OPEN: any error, missing jq, or empty output exits 0 and the command
# proceeds normally. A buggy guard never blocks your shell. Prod-targeted decisions
# are appended to a local audit log.

set -uo pipefail

# ============================ CONFIG — EDIT THIS ==============================
# Case-insensitive extended regexes that mark a PRODUCTION target. Prod is keyed on
# concrete identifiers — the prod AWS account id and "prod" as a DELIMITED token in
# an operational reference (a --context/--profile/--namespace/--host flag, an env
# assignment, or a lakefs://, s3:// or http(s):// target). "prod" must be bounded by
# a start/delimiter and a non-letter/end, so real prod names (prod-us-east-1,
# cloud-prod) match while product / my-product / reproduce / build:production do NOT.
# The prod AWS account id comes from ~/.agents/local.env, kept out of git.
[ -f "$HOME/.agents/local.env" ] && . "$HOME/.agents/local.env"
PROD_PATTERNS=(
  '(--context|--kube-context|--profile|--namespace|--host|--kubeconfig)([[:space:]]+|=)([^[:space:]]*[-_/.:])?prod([^a-z]|$)'  # --flag <value carrying a "prod" token>
  '(KUBECONFIG|AWS_PROFILE|AWS_VAULT|KUBE_CONTEXT|LAKECTL_PROFILE)=([^[:space:]]*[-_/.:])?prod([^a-z]|$)'        # prod-y env var assignment
  '(lakefs://|s3://|https?://)([^[:space:]]*[-_/.])?prod([^a-z]|$)'                                             # "prod" token inside a lakefs/s3/http target
  # 'eks-prod|prod-eks|lakefs-prod'          # add your own prod host/namespace identifiers here
)
# Account id also catches raw-ARN kube contexts.
[ -n "${PROD_AWS_ACCOUNT_ID:-}" ] && PROD_PATTERNS+=("$PROD_AWS_ACCOUNT_ID")

# Case-insensitive regex that marks the ACTIVE kube context as production, used
# by STRICT_KUBE_CONTEXT below. Matched against the bare context NAME (not command
# text), so it must catch both the friendly "prod-*" aliases and the raw-ARN form
# whose only prod signal is the account id.
PROD_CONTEXT_RE="(prod${PROD_AWS_ACCOUNT_ID:+|$PROD_AWS_ACCOUNT_ID})"

# Decision when a prod target meets a non-read-only command:
#   "ask"  -> Claude Code prompts you to confirm (recommended; matches per-action approval)
#   "deny" -> hard block (Claude must change approach)
GUARD_DECISION="${PROD_GUARD_DECISION:-ask}"

# Also treat the *active* kube context as prod when it matches PROD_CONTEXT_RE,
# even if the command never names it — this is how an implicit `kubectl delete pod`
# against a prod cluster gets caught. Only consulted for kubectl/helm commands that
# don't carry their own --context, so it costs one `kubectl config current-context`
# call on those commands (fails open). On by default.
STRICT_KUBE_CONTEXT="${PROD_GUARD_STRICT_KUBE:-true}"
# ==============================================================================

# High-confidence MUTATING commands, matched per segment. This is the gate: a prod
# segment that matches is ASKed (or DENIED if also catastrophic). Keep it reasonably
# complete for the stack (kubectl/helm/aws/eksctl/argocd/pulumi/flux/lakectl/restish/
# terraform/psql/dynamodb) — a mutation via a tool NOT listed here would pass.
MUTATING_RE='(kubectl([[:space:]]|[[:space:]].*[[:space:]])(delete|apply|edit|scale|patch|drain|cordon|uncordon|replace|annotate|label|set|exec|create|cp|rollout[[:space:]]+(restart|undo))([[:space:]]|$)|helm([[:space:]]|[[:space:]].*[[:space:]])(install|upgrade|uninstall|delete|rollback)([[:space:]]|$)|aws[[:space:]].*[[:space:]](delete|put|create|update|remove|terminate|reboot|attach|detach|modify|write|register|deregister|associate|disassociate)[a-z0-9-]*([[:space:]]|$)|aws[[:space:]]+(.*[[:space:]])?s3[[:space:]]+(rm|mv|sync|cp|rb)([[:space:]]|$)|eksctl([[:space:]]|[[:space:]].*[[:space:]])(create|delete|scale|drain|upgrade)([[:space:]]|$)|argocd([[:space:]]|[[:space:]].*[[:space:]])(sync|delete|set|create|rollback)([[:space:]]|$)|pulumi([[:space:]]|[[:space:]].*[[:space:]])(up|destroy|refresh)([[:space:]]|$)|flux([[:space:]]|[[:space:]].*[[:space:]])(reconcile|delete|suspend|resume|bootstrap)([[:space:]]|$)|lakectl([[:space:]]|[[:space:]].*[[:space:]])(commit|merge|import|upload|delete|rm|reset|revert|create|run)([[:space:]]|$)|restish([[:space:]]|[[:space:]].*[[:space:]])(post|put|patch|delete)([[:space:]]|$)|terraform([[:space:]]|[[:space:]].*[[:space:]])(apply|destroy)([[:space:]]|$)|(psql|mysql)[[:space:]].*(insert|update|delete|drop|alter|truncate)|dynamodb[[:space:]].*(put-item|delete-item|update-item|batch-write))'

# CATASTROPHIC, irreversible operations. On a prod target these are hard-DENIED
# (blocked outright) rather than merely asked — run them manually if truly needed.
CATASTROPHIC_RE='(kubectl([[:space:]]|[[:space:]].*[[:space:]])delete([[:space:]]|[[:space:]].*[[:space:]])(namespace|ns|pvc|persistentvolumeclaim|pv|persistentvolume|crd|customresourcedefinition)([[:space:]]|/|$)|kubectl([[:space:]]|[[:space:]].*[[:space:]])delete[[:space:]].*(--all|--all-namespaces)([[:space:]]|$)|helm([[:space:]]|[[:space:]].*[[:space:]])(uninstall|delete)([[:space:]]|$)|terraform([[:space:]]|[[:space:]].*[[:space:]])destroy([[:space:]]|$)|aws[[:space:]]+(.*[[:space:]])?s3[[:space:]]+rb([[:space:]]|$)|aws[[:space:]].*[[:space:]]rds[[:space:]].*delete|aws[[:space:]].*[[:space:]]eks[[:space:]].*delete-cluster|eksctl([[:space:]]|[[:space:]].*[[:space:]])delete[[:space:]]+cluster|dynamodb[[:space:]].*delete-table|(psql|mysql)[[:space:]].*(drop[[:space:]]+(table|database|schema|index)|truncate))'

# Append prod-targeted decisions to a local audit log (best-effort, never blocks).
AUDIT_LOG="${PROD_GUARD_AUDIT_LOG:-$HOME/.claude/prod-audit.log}"
audit() { # $1=decision  ($CMD and $prod_hit come from scope)
  local ts oneline
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" || ts='?'
  oneline="$(printf '%s' "$CMD" | tr '\n\t' '  ')"
  { printf '%s\t%s\t%s\t%s\n' "$ts" "$1" "${prod_hit:-?}" "$oneline" >> "$AUDIT_LOG"; } 2>/dev/null || true
}

# --- read input; fail open on anything unexpected ---------------------------
command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat 2>/dev/null)" || exit 0
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -z "$CMD" ] && exit 0

# --- is a production target referenced? -------------------------------------
prod_hit=""
if [ "${#PROD_PATTERNS[@]}" -gt 0 ]; then
  for p in "${PROD_PATTERNS[@]}"; do
    [ -n "$p" ] || continue
    if printf '%s' "$CMD" | grep -iqE "$p"; then prod_hit="$p"; break; fi
  done
fi

# For a kubectl/helm command that doesn't name its own context, the effective
# target is the active kube context. Consult it and treat a prod context as a prod
# target — even though the command text never says "prod". Commands that carry an
# explicit --context/--kube-context/--kubeconfig are skipped: that target governs
# and is already handled by the command-text match above.
if [ -z "$prod_hit" ] && [ "$STRICT_KUBE_CONTEXT" = "true" ] \
   && printf '%s' "$CMD" | grep -iqE '(^|[[:space:]]|[;&|(])(kubectl|helm)([[:space:]]|$)' \
   && ! printf '%s' "$CMD" | grep -iqE '(--context|--kube-context|--kubeconfig)([[:space:]]|=)' \
   && command -v kubectl >/dev/null 2>&1; then
  ctx="$( (kubectl config current-context 2>/dev/null) || true )"
  if [ -n "$ctx" ] && printf '%s' "$ctx" | grep -iqE "$PROD_CONTEXT_RE"; then
    prod_hit="active kube context '$ctx'"
  fi
fi

[ -z "$prod_hit" ] && exit 0   # no prod target -> defer to normal flow

# --- prod referenced: flag if ANY segment performs a known mutation ----------
# Split on && || ; | and newlines (NOT a bare & — that would shred `2>&1`), then
# check each segment for a mutating/catastrophic op. Per-segment so a mutation
# can't hide behind a read-only token (`... delete ... && echo done`) and so the
# prompt can name which part mutates. Read-only segments — greps (even with
# `a|b` alternations, since we only flag on positive mutation matches), loops,
# pipes, redirects, cd — never match and pass through.
nl=$'\n'
split="${CMD//&&/$nl}"; split="${split//||/$nl}"
catastrophic_seg=""; mutating_seg=""
while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"   # ltrim
  seg="${seg%"${seg##*[![:space:]]}"}"   # rtrim
  [ -z "$seg" ] && continue
  if [ -z "$catastrophic_seg" ] && printf '%s' "$seg" | grep -iqE "$CATASTROPHIC_RE"; then
    catastrophic_seg="$seg"
  elif [ -z "$mutating_seg" ] && printf '%s' "$seg" | grep -iqE "$MUTATING_RE"; then
    mutating_seg="$seg"
  fi
done < <(printf '%s\n' "$split" | tr ';|' '\n')

# no mutating/catastrophic segment on a prod target -> allow
if [ -z "$catastrophic_seg$mutating_seg" ]; then
  audit "pass"
  exit 0
fi

# --- name the offending segment; DENY catastrophic, else ASK -----------------
if [ "${prod_hit#active kube context}" != "$prod_hit" ]; then
  prodwhy="$prod_hit"          # e.g. active kube context 'prod-us-east-1'
else
  prodwhy="a production target"
fi

if [ -n "$catastrophic_seg" ]; then
  decision="deny"; culprit="$catastrophic_seg"; why="a CATASTROPHIC, irreversible operation"
else
  decision="$GUARD_DECISION"; culprit="$mutating_seg"; why="a MUTATING command"
fi
show="$culprit"; [ "${#show}" -gt 120 ] && show="${show:0:117}..."

if [ "$decision" = "deny" ]; then
  reason="⛔ BLOCKED: «${show}» is ${why} against ${prodwhy}. If truly required, run it manually outside Claude or temporarily disable the guard."
else
  reason="⚠ Gated command: «${show}» — ${why} against ${prodwhy}. Other segments pass; approve only if intended (production changes need per-action approval)."
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
