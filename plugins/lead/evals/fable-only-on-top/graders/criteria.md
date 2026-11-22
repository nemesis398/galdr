---
type: llm
weight: 1
---

The response dispatches:

- A on a reviewer subagent (`lead:review` or equivalent) with Opus at xhigh
  effort, rung 6, and explicitly not Fable;
- B on a reviewer subagent with Fable at high effort, rung 7.

It fails if A runs on Fable, if B runs on anything but Fable, or if either
review is done by the lead itself instead of a subagent.
