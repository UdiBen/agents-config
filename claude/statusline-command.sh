#!/usr/bin/env bash
# Description: Claude Code status line - 2-line layout
#   Line 1: 📁 path (up to 3 components) | 🌿 branch [status] | PR info
#   Line 2: model [effort] | context bar XX%

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')

# Shorten model name: "Claude Opus 4.6" -> "Opus 4.6"
model_short=$(echo "$model" | sed 's/[Cc]laude //')

# Path: last 3 components, with ~ for home
home="$HOME"
short_path="${cwd/#$home/~}"
IFS='/' read -ra parts <<< "$short_path"
n=${#parts[@]}
if [ "$n" -gt 4 ]; then
  short_path="${parts[$((n-4))]}/${parts[$((n-3))]}/${parts[$((n-2))]}/${parts[$((n-1))]}"
fi

# Git info
branch=""
status_str=""
if git -C "$cwd" -c core.hooksPath=/dev/null rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)

  staged=$(git -C "$cwd" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
  modified=$(git -C "$cwd" diff --name-only 2>/dev/null | wc -l | tr -d ' ')
  untracked=$(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
  deleted=$(git -C "$cwd" ls-files --deleted 2>/dev/null | wc -l | tr -d ' ')

  [ "$staged" -gt 0 ]    && status_str="${status_str}+${staged}"
  [ "$modified" -gt 0 ]  && status_str="${status_str}~${modified}"
  [ "$deleted" -gt 0 ]   && status_str="${status_str}-${deleted}"
  [ "$untracked" -gt 0 ] && status_str="${status_str}?${untracked}"
fi

# PR info: cached per repo+branch, refreshed asynchronously so the statusline
# never blocks on gh. TTL 60s. Missing-PR results are cached too (as {}) to
# avoid hammering gh for branches without a PR.
pr_part=""
pr_url=""
if [ -n "$branch" ] && command -v gh >/dev/null 2>&1; then
  repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$repo_root" ]; then
    cache_dir="${TMPDIR:-/tmp}/claude-statusline-pr"
    mkdir -p "$cache_dir" 2>/dev/null
    cache_key=$(printf '%s__%s' "$repo_root" "$branch" | shasum | cut -d' ' -f1)
    cache_file="${cache_dir}/${cache_key}"
    lock_file="${cache_file}.lock"

    needs_refresh=1
    if [ -f "$cache_file" ]; then
      mtime=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)
      age=$(( $(date +%s) - mtime ))
      [ "$age" -lt 60 ] && needs_refresh=0
    fi

    if [ "$needs_refresh" -eq 1 ] && [ ! -f "$lock_file" ]; then
      (
        touch "$lock_file"
        result=$(cd "$repo_root" && gh pr view "$branch" --json number,state,isDraft,reviewDecision,url 2>/dev/null)
        if [ -n "$result" ]; then
          printf '%s' "$result" > "$cache_file"
        else
          printf '{}' > "$cache_file"
        fi
        rm -f "$lock_file"
      ) >/dev/null 2>&1 &
      disown 2>/dev/null || true
    fi

    if [ -f "$cache_file" ]; then
      pr_json=$(cat "$cache_file" 2>/dev/null)
      pr_num=$(printf '%s' "$pr_json" | jq -r '.number // empty' 2>/dev/null)
      if [ -n "$pr_num" ]; then
        pr_state=$(printf '%s' "$pr_json" | jq -r '.state // empty')
        pr_draft=$(printf '%s' "$pr_json" | jq -r '.isDraft // false')
        pr_review=$(printf '%s' "$pr_json" | jq -r '.reviewDecision // empty')
        pr_url=$(printf '%s' "$pr_json" | jq -r '.url // empty')

        case "$pr_state" in
          MERGED) pr_label="MERGED" ;;
          CLOSED) pr_label="CLOSED" ;;
          *)      [ "$pr_draft" = "true" ] && pr_label="DRAFT" || pr_label="OPEN" ;;
        esac
        case "$pr_review" in
          APPROVED)          pr_label="${pr_label} ✓" ;;
          CHANGES_REQUESTED) pr_label="${pr_label} ✗" ;;
        esac
        pr_part="#${pr_num} ${pr_label}"
      fi
    fi
  fi
fi

# Colors
CYAN=$'\033[36m'
MAGENTA=$'\033[35m'
RED=$'\033[31m'
GREEN=$'\033[32m'
BLUE=$'\033[34m'
PURPLE=$'\033[38;5;141m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# Smooth gradient context bar: eighth-block fractional fill, colored per cell
# so the gradient brightens toward the fill tip. Color zone tracks usage.
make_bar() {
  local pct=$1 width=12 ramp bright
  if   [ "$pct" -ge 90 ]; then ramp=(88 124 131 174);   bright=174
  elif [ "$pct" -ge 70 ]; then ramp=(94 130 136 179);   bright=179
  else                          ramp=(65 71 72 78);     bright=78
  fi
  local rlen=${#ramp[@]}
  local eighths=$(( pct * width * 8 / 100 ))
  local full=$(( eighths / 8 ))
  local rem=$(( eighths % 8 ))
  local fracs=(' ' '▏' '▎' '▍' '▌' '▋' '▊' '▉')
  local out="" i ci
  for (( i=0; i<width; i++ )); do
    if [ "$i" -lt "$full" ]; then
      if [ "$full" -gt 1 ]; then ci=$(( i * (rlen-1) / (full-1) )); else ci=$(( rlen-1 )); fi
      out+=$'\033[38;5;'"${ramp[$ci]}"'m█'
    elif [ "$i" -eq "$full" ] && [ "$rem" -gt 0 ]; then
      out+=$'\033[38;5;'"${bright}"'m'"${fracs[$rem]}"
    else
      out+=$'\033[38;5;236m░'
    fi
  done
  out+=$' \033[38;5;'"${bright}"'m'"${pct}%"$'\033[0m'
  printf '%s' "$out"
}

# --- active AWS environment (shared with the shell prompt) --------------------
# Reflects whether aws commands can run in this session, via aws.current (reads
# this env's AWS_PROFILE + token expiry from credentials; all local, no network).
aws_env=$("$HOME/scripts/aws/aws.current" 2>/dev/null || echo Inactive)

# --- production detection (drives the dedicated banner line) -----------------
# In prod if the active kube context is a prod cluster OR the active AWS login is
# Production. Sources are labelled so it's clear which fired: k8s / aws.
prod_srcs=""
# The prod AWS account id comes from ~/.agents/local.env, kept out of git.
[ -f "$HOME/.agents/local.env" ] && . "$HOME/.agents/local.env"
if command -v kubectl >/dev/null 2>&1; then
  kctx=$(kubectl config current-context 2>/dev/null)
  [ -n "$kctx" ] && printf '%s' "$kctx" | grep -iqE "(prod${PROD_AWS_ACCOUNT_ID:+|$PROD_AWS_ACCOUNT_ID})" && prod_srcs="k8s"
fi
[ "$aws_env" = "Production" ] && prod_srcs="${prod_srcs:+$prod_srcs+}aws"
prod_banner=""
if [ -n "$prod_srcs" ]; then
  # bold bright-white on a vivid 256-color red (196) — explicit color so the
  # terminal theme can't mute it; on its own line so it cannot be missed.
  REVRED=$'\033[1;38;5;231;48;5;196m'
  prod_banner="${REVRED}  ⛔  PRODUCTION  ·  ${prod_srcs}  ⛔  ${RESET}"
fi

# ── Line 1: 📁 path | 🌿 branch [status] | PR info ───────────────────────────
line1="📁 ${CYAN}${BOLD}${short_path}${RESET}"
if [ -n "$branch" ]; then
  git_rendered="🌿 ${MAGENTA}${branch}${RESET}"
  [ -n "$status_str" ] && git_rendered="${git_rendered} ${RED}[${status_str}]${RESET}"
  line1="${line1} ${DIM}|${RESET} ${git_rendered}"
fi
# AWS environment chip (after the branch), colored by risk.
case "$aws_env" in
  Production)  aws_color=$'\033[1;38;5;196m' ;;  # bold vivid red
  Staging)     aws_color=$'\033[38;5;179m' ;;    # amber
  Development) aws_color=$'\033[38;5;78m' ;;      # green
  Expired)     aws_color=$'\033[38;5;173m' ;;     # orange
  *)           aws_color="$DIM" ;;                # Inactive / unknown
esac
line1="${line1} ${DIM}|${RESET} ☁️ ${aws_color}${aws_env}${RESET}"
if [ -n "$pr_part" ]; then
  pr_color="$GREEN"
  case "$pr_state" in
    MERGED) pr_color="$PURPLE" ;;
    CLOSED) pr_color="$RED" ;;
    *)      [ "$pr_draft" = "true" ] && pr_color="$DIM" ;;
  esac
  # OSC 8 hyperlink if terminal supports it (iTerm2, WezTerm, Kitty, VSCode, recent Terminal.app)
  if [ -n "$pr_url" ]; then
    ESC=$'\033'
    BEL=$'\a'
    pr_rendered="${ESC}]8;;${pr_url}${BEL}${pr_part}${ESC}]8;;${BEL}"
  else
    pr_rendered="$pr_part"
  fi
  line1="${line1} ${DIM}|${RESET} 🔀 ${pr_color}${pr_rendered}${RESET}"
fi

# ── Line 2: 🤖 model [effort] | context bar XX% | session id ──────────────────
line2="🤖 ${BLUE}${model_short}${RESET}"
if [ -n "$effort" ]; then
  case "$effort" in
    low)    eff_color=$'\033[38;5;78m'  ;;  # green
    medium) eff_color=$'\033[38;5;179m' ;;  # amber
    high)   eff_color=$'\033[38;5;173m' ;;  # orange
    xhigh)  eff_color=$'\033[38;5;174m' ;;  # red-pink
    max)    eff_color=$'\033[38;5;204m' ;;  # magenta-red
    *)      eff_color="$DIM" ;;
  esac
  line2="${line2} ${DIM}[${RESET}${eff_color}${effort}${RESET}${DIM}]${RESET}"
fi
if [ -n "$used_pct" ]; then
  ctx_int=$(printf '%.0f' "$used_pct")
  line2="${line2} ${DIM}|${RESET} $(make_bar "$ctx_int")"
fi
if [ -n "$session_id" ]; then
  line2="${line2} ${DIM}|${RESET} ${DIM}${session_id}${RESET}"
fi

# When in production, prepend a dedicated banner line (3 lines total); the banner
# is the entire first line.
if [ -n "$prod_banner" ]; then
  printf '%s\n%s\n%s' "$prod_banner" "$line1" "$line2"
else
  printf '%s\n%s' "$line1" "$line2"
fi
