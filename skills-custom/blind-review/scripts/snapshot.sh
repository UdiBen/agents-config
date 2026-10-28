#!/usr/bin/env bash
# Snapshot a changeset for blind-review into a fresh run directory.
#
# Usage: snapshot.sh <scratch-root> [--base <branch>] [<PR: number | owner/repo#N | URL>]
#
# Writes <run>/env.sh, snapshot.diff, paths.txt, claims.md and, when a PR exists, pr.json.
# Prints only the run directory, the target line and the shape. Never prints code.
set -euo pipefail

die() { echo "blind-review: $*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: snapshot.sh <scratch-root> [--base <branch>] [<pr>]"
ROOT=$1; shift
BASE_ARG=""; PR_ARG=""
while [ $# -gt 0 ]; do
  case $1 in
    --base) BASE_ARG=${2:?--base needs a branch}; shift 2 ;;
    *) PR_ARG=$1; shift ;;
  esac
done

command -v gh >/dev/null || die "gh is not installed"
command -v jq >/dev/null || die "jq is not installed"

REPO=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
cd "$REPO"
NWO=$(gh repo view --json nameWithOwner -q .nameWithOwner) || die "gh cannot resolve this repository"
OWNER=${NWO%/*}; NAME=${NWO#*/}

RUN="$ROOT/blind-review-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$RUN"

git fetch origin --quiet || die "git fetch origin failed"
DEFAULT=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)
DEFAULT=${DEFAULT:-$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)}

PR_FIELDS=number,title,body,url,baseRefName,headRefName,headRefOid,isDraft,isCrossRepository,headRepositoryOwner,closingIssuesReferences

if [ -n "$PR_ARG" ]; then
  MODE=pr
  case $PR_ARG in
    https://github.com/*/pull/*)
      PR_REPO=$(sed -E 's#https://github.com/([^/]+/[^/]+)/pull/.*#\1#' <<<"$PR_ARG")
      NUM=$(sed -E 's#.*/pull/([0-9]+).*#\1#' <<<"$PR_ARG") ;;
    */*#*) PR_REPO=${PR_ARG%#*}; NUM=${PR_ARG#*#} ;;
    *) PR_REPO=$NWO; NUM=${PR_ARG#\#} ;;
  esac
  [[ $NUM =~ ^[0-9]+$ ]] || die "cannot read a PR number from '$PR_ARG'"
  [ "$(tr '[:upper:]' '[:lower:]' <<<"$PR_REPO")" = "$(tr '[:upper:]' '[:lower:]' <<<"$NWO")" ] \
    || die "PR is in $PR_REPO; run from a checkout of that repository"
  gh pr view "$NUM" --repo "$NWO" --json "$PR_FIELDS" > "$RUN/pr.json"
  BASE_REF=${BASE_ARG:-$(jq -r .baseRefName "$RUN/pr.json")}
  git fetch origin --quiet "refs/pull/$NUM/head"
  HEAD_SHA=$(git rev-parse FETCH_HEAD)
  git fetch origin --quiet "$BASE_REF"
  HEAD_REF=$(jq -r .headRefName "$RUN/pr.json")
  if [ "$(jq -r .isCrossRepository "$RUN/pr.json")" = true ]; then
    SLUG="$(jq -r .headRepositoryOwner.login "$RUN/pr.json")-$HEAD_REF"
  else
    SLUG=$HEAD_REF
  fi
  AGENT_ROOT="$RUN/worktree"
  git worktree add --detach --quiet "$AGENT_ROOT" "$HEAD_SHA"
  TARGET="PR #$NUM ($HEAD_REF)"
  TREE="PR head, clean"
else
  MODE=branch
  HEAD_REF=$(git branch --show-current)
  [ -n "$HEAD_REF" ] || die "HEAD is detached; check out a branch or pass a PR"
  [ "$HEAD_REF" != "$DEFAULT" ] || die "on $DEFAULT with no PR given: nothing to review"
  gh pr view --json "$PR_FIELDS" > "$RUN/pr.json" 2>/dev/null || rm -f "$RUN/pr.json"
  BASE_REF=$BASE_ARG
  [ -z "$BASE_REF" ] && [ -f "$RUN/pr.json" ] && BASE_REF=$(jq -r .baseRefName "$RUN/pr.json")
  BASE_REF=${BASE_REF:-$DEFAULT}
  HEAD_SHA=$(git rev-parse HEAD)
  SLUG=$HEAD_REF
  AGENT_ROOT=$REPO
  TARGET="$HEAD_REF"
  PORC=$(git status --porcelain)
  STAGED=$(grep -cE '^[MADRC]' <<<"$PORC" || true)
  UNSTAGED=$(grep -cE '^.[MD]' <<<"$PORC" || true)
  UNTRACKED=$(grep -c '^??' <<<"$PORC" || true)
  if [ -z "$PORC" ]; then TREE=clean; else TREE="dirty: $STAGED staged / $UNSTAGED unstaged / $UNTRACKED untracked"; fi
fi

SLUG=$(tr '/' '-' <<<"$SLUG")
BASE_TIP=$(git rev-parse --verify -q "origin/$BASE_REF" || git rev-parse --verify -q "$BASE_REF") \
  || die "base '$BASE_REF' not found locally or on origin"
BASE=$(git merge-base "$BASE_TIP" "$HEAD_SHA")

# Snapshot and numstat. Untracked files are diffed against /dev/null; that exits 1 by design.
SNAP="$RUN/snapshot.diff"
NUMSTAT="$RUN/numstat.txt"
{
  echo "### target: $TARGET @ ${HEAD_SHA:0:12} — base: $BASE_REF (${BASE:0:12}) — tree: $TREE"
  echo "### committed"
  git diff "$BASE" "$HEAD_SHA"
  if [ "$MODE" = branch ]; then
    echo "### uncommitted"
    git diff HEAD
    echo "### untracked"
    git ls-files -z --others --exclude-standard | while IFS= read -r -d '' f; do
      git diff --no-index -- /dev/null "$f" || true
    done
  fi
} > "$SNAP"
if [ "$MODE" = branch ]; then
  {
    git diff --numstat "$BASE"
    git ls-files -z --others --exclude-standard | while IFS= read -r -d '' f; do
      git diff --no-index --numstat -- /dev/null "$f" || true
    done
  } > "$NUMSTAT"
  { git diff --name-only "$BASE"; git ls-files --others --exclude-standard; } | sort -u > "$RUN/paths.txt"
else
  git diff --numstat "$BASE" "$HEAD_SHA" > "$NUMSTAT"
  git diff --name-only "$BASE" "$HEAD_SHA" | sort -u > "$RUN/paths.txt"
fi
CHANGED=$(awk -F'\t' '{a=($1=="-")?0:$1; d=($2=="-")?0:$2; s+=a+d} END {print s+0}' "$NUMSTAT")

# Claims: issue numbers from the PR's closing references, commit trailers, then the branch name.
LOG="$RUN/commits.txt"
git log --format='- %s%n%b' "$BASE..$HEAD_SHA" > "$LOG"
ISSUES=""
ISSUE_SOURCE=""
if [ -f "$RUN/pr.json" ]; then
  ISSUES=$(jq -r '.closingIssuesReferences[]?.number' "$RUN/pr.json" | sort -un | paste -sd' ' -)
  [ -n "$ISSUES" ] && ISSUE_SOURCE="the PR's closing references"
fi
if [ -z "$ISSUES" ]; then
  ISSUES=$(grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?) #[0-9]+' "$LOG" | grep -oE '[0-9]+' | sort -un | paste -sd' ' - || true)
  [ -n "$ISSUES" ] && ISSUE_SOURCE="commit messages"
fi
if [ -z "$ISSUES" ]; then
  ISSUES=$(grep -oE '(^|[/_-])[0-9]{2,}([/_-]|$)' <<<"$HEAD_REF" | grep -oE '[0-9]+' | head -1 || true)
  [ -n "$ISSUES" ] && ISSUE_SOURCE="the branch name (a guess)"
fi

CLAIMS="$RUN/claims.md"
{
  echo "# Claims — test each against the diff; none of this is context"
  if [ -f "$RUN/pr.json" ]; then
    echo; echo "## PR description (the author's claim)"
    jq -r '"### " + .title + "\n\n" + (.body // "")' "$RUN/pr.json"
  fi
  for n in $ISSUES; do
    body=$(gh issue view "$n" --repo "$NWO" --json title,body -q '"### #'"$n"' " + .title + "\n\n" + (.body // "")' 2>/dev/null) || continue
    echo; echo "## Issue #$n — what was asked (found via $ISSUE_SOURCE)"
    echo "$body"
    parents=$(gh api graphql -H 'GraphQL-Features: sub_issues' \
      -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){parent{number title body parent{number title body}}}}}' \
      -F o="$OWNER" -F r="$NAME" -F n="$n" \
      --jq '.data.repository.issue.parent | select(.) | ., (.parent | select(.)) | "### #\(.number) \(.title)\n\n\(.body // "")\n"' 2>/dev/null || true)
    if [ -n "$parents" ]; then
      echo; echo "## Parent issues of #$n — the planned sequence; groundwork with no caller yet may be the plan"
      echo "$parents"
    fi
  done
  echo; echo "## Commit messages"
  cat "$LOG"
} > "$CLAIMS"

# Round history is per branch, in the repository's shared git directory, so every worktree sees it.
HIST_DIR="$(cd "$(git rev-parse --git-common-dir)" && pwd)/blind-review/$SLUG"
PREV_N=$({ ls "$HIST_DIR"/r*.json 2>/dev/null || true; } | sed -E 's#.*/r([0-9]+)\.json#\1#' | sort -n | tail -1)
PREV_N=${PREV_N:-0}

{
  printf 'RUN=%q\nMODE=%q\nREPO=%q\nNWO=%q\nAGENT_ROOT=%q\nSNAP=%q\nCLAIMS=%q\n' \
    "$RUN" "$MODE" "$REPO" "$NWO" "$AGENT_ROOT" "$SNAP" "$CLAIMS"
  printf 'TARGET=%q\nSLUG=%q\nHEAD_REF=%q\nHEAD_SHA=%q\nBASE_REF=%q\nBASE=%q\nTREE=%q\n' \
    "$TARGET" "$SLUG" "$HEAD_REF" "$HEAD_SHA" "$BASE_REF" "$BASE" "$TREE"
  printf 'CHANGED=%q\nHIST_DIR=%q\nPREV_N=%q\n' "$CHANGED" "$HIST_DIR" "$PREV_N"
} > "$RUN/env.sh"

TESTS=$(grep -cE '(_test\.go|_test\.py|test_[^/]*\.py|\.(test|spec)\.[cm]?[jt]sx?|(^|/)tests?/)' "$RUN/paths.txt" || true)
RISKY=$(grep -ciE '(auth|permission|acl|rbac|policy|security|crypto|secret|token|session|login|oauth|oidc|saml|password|credential|(^|/)api/|gateway|middleware|handler)' "$RUN/paths.txt" || true)

echo "run: $RUN"
echo "agent repo root: $AGENT_ROOT"
head -1 "$SNAP"
echo "changed lines: $CHANGED  changed paths: $(wc -l < "$RUN/paths.txt" | tr -d ' ')  test paths: $TESTS  security-sensitive paths: $RISKY"
echo "issues: ${ISSUES:-none found}${ISSUE_SOURCE:+ (from $ISSUE_SOURCE)}"
if [ "$PREV_N" -gt 0 ]; then echo "previous round: r$PREV_N ($HIST_DIR/r$PREV_N.json)"; else echo "previous round: none"; fi
cat "$RUN/paths.txt"
