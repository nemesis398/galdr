---
max_turns: 6
allowed_tools: [Skill, Read]
---

I am running an implementation plan with subagents, and you are the lead. Task
2 (`docs/plan.md`, "Task 2", tagged `(edit)`) renames `fetch_user` to
`load_user` across nine files. It went to a `lead:edit` worker at its start
rung, Haiku at low effort. The worker finished, but the task's gate,
`pytest -q`, is red: two call sites in `api/routes.py` still use `fetch_user`.
For answer 1, this is not a job to do yourself: pytest stops at the first module that fails
to import, so more stale call sites may hide in the nine files, and finding
and fixing them all is well over a dozen tool calls of your expensive context.

1. What is your next move? Give the exact tool call with every parameter
   (agent type, model, effort) and the prompt you would send.
2. Suppose instead that this same failure came back from a `lead:edit` worker
   that ran on Sonnet at high effort. What is your next move then?

You cannot call any tool here but Skill and Read, so describe the moves
instead of making them.
