---
name: render-mermaid-in-md
description: When creating a knowledge/reference MD file and you opt to use Mermaid for a diagram, render it to PNG with `mmdc` and embed the image; keep the Mermaid source in a collapsed details block
metadata:
  type: feedback
---

When writing a knowledge MD file (typically under `~/code/treeverse/knowledge/`) and choosing Mermaid for a diagram, do not stop at a ` ```mermaid ` code block — also render the diagram to an image and embed it.

**Why:** Many viewers (Arc browser, plain Finder Quick Look, GitHub raw view, terminal previewers) don't render Mermaid. The user wants to see the diagram immediately without configuring a Mermaid-aware viewer. ASCII fallbacks don't work either — they look broken in proportional fonts.

**How to apply:**
1. Write the Mermaid source to a temp `.mmd` file.
2. Render via Homebrew's `mmdc` (system-wide, not tied to nvm node version):
   ```
   /opt/homebrew/bin/mmdc -i /tmp/diagram.mmd -o ~/code/treeverse/knowledge/<name>.png -w 1600 -b white
   ```
   Use the brew binary path explicitly because the nvm `mmdc` may be a different version and shadow it in PATH.
3. In the MD file, embed the image with a relative path: `![alt](<name>.png)`.
4. Keep the Mermaid source inside `<details><summary>Mermaid source</summary> ... </details>` below the image, so it's editable but doesn't clutter the rendered view.

Opening the file in Arc afterward is handled automatically by a PostToolUse hook on writes under `~/code/treeverse/knowledge/`.

**Don't apply when:**
- The user explicitly asks for raw Mermaid only (e.g. for a GitHub README where they want native rendering).
- The diagram is trivial enough that ASCII inside a fenced code block is clearer (small box-and-arrow, table, etc.) — those don't need Mermaid at all.
