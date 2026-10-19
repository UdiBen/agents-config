---
name: handoff
description: Save the current session's full working context to a handoff markdown file at `~/.claude/handoff/<SESSION_ID>.md`, then tell the user to run `/compact`. The file path is printed prominently so the compaction summary preserves it and the post-compact session can read the file to resume. Use when the user asks for a "handoff", "session handoff", "save session before compact", "dump session", "prep compact", or signals they're near the context window and want to continue in a fresh compacted session.
---

# handoff

Capture everything from this session into a handoff file. The user will run `/compact` themselves; print the path prominently so the compaction summary carries it forward and the post-compact session can read the file to continue.

## Workflow

1. **Resolve paths** - derive session id from the most recently modified transcript for this project:

   ```bash
   PROJECT_DIR="$HOME/.claude/projects/-$(pwd | sed 's|^/||; s|/|-|g')"
   SESSION_ID=$(ls -t "$PROJECT_DIR"/*.jsonl 2>/dev/null | head -1 | xargs -I{} basename {} .jsonl)
   DIR="$HOME/.claude/handoff"
   mkdir -p "$DIR"
   HANDOFF="$DIR/$SESSION_ID.md"
   echo "$HANDOFF"
   ```

   If `$SESSION_ID` is empty, abort and tell the user - don't fall back silently.

2. **Write the handoff** to `$HANDOFF` using the Write tool. Cover all of:

   - **Goal & status** - what the user set out to do; where things stand right now
   - **Files changed** - paths created/modified/deleted, one-line description each
   - **Config modifications** - settings, env vars, hooks, deps updated
   - **Commands executed** - non-trivial commands, especially mutating ones
   - **Steps taken** - chronological narrative of what was worked through
   - **Decisions** - choices made and the reasoning
   - **Dead ends** - things tried that didn't work, so they aren't retried
   - **Verification status** - what's been tested/run vs. still pending
   - **Open todos / next steps** - what's pending; what should happen next
   - **Branch & git state** - branch name; one-line `git status` summary
   - **Ids & specific data** - actual ids you used/fetched/updated (entities, data etc.)

   Be thorough but tight: bullets and short paragraphs, not prose. The reader is your future self in a compacted session - write what you'd want to know to pick up cold. Reflect the **whole** session, not just recent turns.

3. **Print exactly** (substituting the real `$HANDOFF` path):

   ```
   Handoff saved at <HANDOFF>.
   After /compact, read this file in full to resume the session.
   Run `/compact` when ready.
   ```

   Nothing else above or below. The path must appear verbatim - the compaction summary needs it to be picked up.

## Notes

- Handoff path: `~/.claude/handoff/<SESSION_ID>.md`.
- Old handoffs are preserved; never delete them.
