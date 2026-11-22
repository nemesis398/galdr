---
type: llm
weight: 1
---

The response sends the fix to a fresh worker:

- the next move is a new Agent call, not SendMessage, a resume, or any message
  to the finished agent `a7f3c2`;
- the prompt it would send carries a fix list with both defects, each naming
  where it is, what is wrong, and what correct looks like;
- the prompt is short and points at the plan's Task 4 section instead of
  retelling the whole task;
- it names a check to run before the worker finishes (the tests).
- the fixer is not set above the task's rung: `lead:build` with no `model` or
  `effort` (its start rung), or Sonnet at medium; Sonnet at high, Opus or
  Fable is above it.

Reusing or messaging `a7f3c2` in any way fails. A fixer set above the task's
rung fails. Fixing the code itself instead of dispatching also fails.
