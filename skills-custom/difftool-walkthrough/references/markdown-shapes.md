# Markdown and code-shape choices

Read this reference when the question involves an exact comparison or small code shape and Markdown
is a plausible candidate, including when concise prose may still win. These are examples and
tie-breakers, not an allowed list.

| Example need | Strong starting point |
|---|---|
| one cause, consequence, caveat, or invariant | a short paragraph |
| peer facts | bullets |
| steps where order matters | a numbered list |
| exact before/after values, shared attributes, or a compatibility cross-product | a table |
| exact requirement wording or a non-line-specific callout | a blockquote |
| secondary provenance | a link or footnote |
| secondary evidence that would interrupt the story | `<details><summary>`, only in a component-free stop |
| intentionally deferred work | a task list |
| a small call, config, query, payload, or wire shape | a language code fence |
| one small algorithm, call path, or ownership tree | a `text` or language code fence |
| the delta in a small code or conceptual shape | a `diff` fence |

For example, prose can carry a short causal chain:

> `loadSession` could return an expired entry while refresh was running, so `authorizeRequest`
> could accept stale permissions. The new expiry check rejects that entry before return. Valid
> entries keep the same path.

Show one local decision path as pseudocode:

```text
on(save)
  if content is unchanged
    return cached result
  write new content
  return fresh result
```

Show a shallow runtime path as a call tree:

```text
submitForm
  createSession
    persistPrompt
    launchAgent
  navigateToSession
```

Keep nesting when it carries ownership or call semantics. Do not flatten this tree into one arrow
chain: that would imply that `submitForm` directly calls every nested operation.

Show UI ownership, state, and relevant module boundaries as a component tree:

```tsx
<SessionPage> (apps/example/src/routes/session.tsx)
  useSessionEvents()
  <SessionToolbar>
    <RunSkillButton> (packages/ui)
```

When the changed shape is the point, use a schematic diff:

```diff
 submitForm
   createSession
     persistPrompt
+    expandSkillMention
     launchAgent
-  navigateToSession
+  navigateToSession
+    subscribeToEvents
```

Distinguish the nearby small-code forms by the question they answer:

- Use pseudocode for one local rule, decision, or algorithm when literal syntax is irrelevant.
- Use a compact outcome table when one local call has a few flat results and the exact effect of each
  result matters more than routing topology.
- Use a call tree for runtime nesting or ownership. Sibling order in a tree does not prove temporal
  order; use a numbered sequence or a sequence diagram when time order is material.
- Use a component tree for UI composition, state ownership, and module boundaries.
- Use a schematic `diff` when a few changes inside a mostly preserved shape are the point.
- Show separate before/after blocks only when each complete state must stand alone. Show one whole
  block when most of it is new, omitted context would hide ownership or order, or the reviewer needs
  a copyable target shape.

Label pseudocode and schematic structures so they are not mistaken for literal source or runnable
code. Keep excerpts small because the live hunk already shows the source.

A local guard or flat result switch can remain prose, pseudocode, or a small outcome table. Use
Mermaid when the topology itself matters—for example, paths rejoin or loop, messages cross actors,
or state transitions carry the explanation. Use **bold** for a short label or fact the eye must
find, *italic* for light emphasis or a newly defined term, and inline code for symbols. Other
supported Markdown shapes remain valid when they communicate the question more clearly.
