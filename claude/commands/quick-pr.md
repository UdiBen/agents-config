Quickly ship changes as a PR in an isolated worktree. Follow this workflow precisely.

## Step 1: Understand the changes

The user said: $ARGUMENTS

If $ARGUMENTS is empty or unclear, ask the user what changes they want. The changes could be:
- **Already staged files** in the current repo — you'll cherry-pick/apply them in the worktree
- **Unstaged modifications** in the current repo — you'll apply them in the worktree
- **New work to implement** — you'll write the code from scratch in the worktree

Ask clarifying questions until you understand exactly what to do. If the request is clear, proceed.

## Step 2: Detect the base branch

Run `git remote show origin | grep 'HEAD branch'` to detect the default branch (main/master/etc).

## Step 3: Capture changes (if applicable)

If the changes already exist in the current working tree (staged or unstaged):
- Create a patch: `git diff > /tmp/quick-pr-unstaged.patch` and/or `git diff --cached > /tmp/quick-pr-staged.patch`
- Remember which files are involved

If the changes need to be implemented from scratch, skip this step.

## Step 4: Create a worktree with a new branch

- Pick a concise kebab-case branch name (follow the Branch Naming convention in CLAUDE.md)
- Confirm the branch name with the user before proceeding
- Create the worktree: `git worktree add /tmp/quick-pr-<branch-name> -b <branch-name> origin/<base-branch>`

## Step 5: Apply or implement changes

In the worktree directory:
- If you have patches, apply them: `git apply /tmp/quick-pr-*.patch`
- If implementing new work, write the code now
- Verify the changes look correct

## Step 6: Commit and push

- Stage the relevant files (use specific file names, not `git add .`)
- Commit with a clear message following the repo's commit style
- Push: `git push -u origin <branch-name>`

## Step 7: Create the PR

Use `gh pr create` with:
- A concise title
- A concise description (follow PR Description conventions in CLAUDE.md)
- Labels: `minor-change`, `exclude-changelog`, `mostly-ai`

Example:
```
gh pr create --title "the pr title" --body "$(cat <<'EOF'
## Summary
<1-3 bullet points>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)" --label "minor-change" --label "exclude-changelog" --label "mostly-ai"
```

## Step 8: Cleanup

- Return to the original working directory
- Remove the worktree: `git worktree remove /tmp/quick-pr-<branch-name>`
- Clean up any patch files in /tmp

## Step 9: Done

Print the PR URL so the user can review it.
