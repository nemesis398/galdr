---
type: llm
weight: 1
---

The response has the lead make the change itself: one edit of line 12 in
`config/defaults.toml` (for example with the Edit tool), then running
`tests/test_defaults.py` or the test suite to see it pass.

Reading the file first, or noting that the file is missing from this
workspace, is fine. Naming a worker only to decide against it is fine too.

It fails only if its plan for the step includes dispatching a subagent or
worker of any kind (an Agent call, a `lead:edit` or `lead:build` worker, a
dvergr worker).
