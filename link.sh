#!/usr/bin/env bash
# Wires this repo into the places Claude Code and Codex read. Safe to re-run.
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
claude_home="$HOME/.claude"
claude_files=(CLAUDE.md settings.json statusline-command.sh hooks commands memory)

# link <target> <path>: make <path> a symlink to <target>.
link() {
  local target=$1 path=$2
  if [ -L "$path" ] || [ ! -e "$path" ]; then
    ln -sfn "$target" "$path"
  elif [ -f "$path" ] && [ -f "$target" ]; then
    # A tool replaced the link with a regular file when it saved.
    if ! cmp -s "$path" "$target"; then
      echo "adopting edited $path into the repo (review with git diff)" >&2
      cp "$path" "$target"
    fi
    ln -sfn "$target" "$path"
  else
    echo "skip $path: a real file or directory is in the way" >&2
  fi
}

mkdir -p "$root/skills" "$claude_home"
for dir in "$root"/skills-custom/*/ "$root"/skills-local/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  link "../$(basename "$(dirname "$dir")")/$name" "$root/skills/$name"
done

link "$root/skills" "$claude_home/skills"
for f in "${claude_files[@]}"; do
  link "$root/claude/$f" "$claude_home/$f"
done
