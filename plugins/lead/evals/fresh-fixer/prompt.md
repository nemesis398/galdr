---
max_turns: 6
allowed_tools: [Skill, Read]
---

I am running an implementation plan with subagents, and you are the lead.
Task 4 of the plan (`docs/plan.md`, section "Task 4") went to a `lead:build`
worker at its start rung (Sonnet, medium effort), agent id `a7f3c2`. It finished, reported its tests green, and its
notification has arrived.

My read of its diff found two defects:

1. `src/parse.py`, `split_fields()`: an empty input raises `IndexError`; it
   should return an empty list.
2. `tests/test_parse.py` has no case for an empty input.

You cannot call any tool here but Skill and Read, so describe your next move
instead of making it: the exact tool you would call, with every parameter
(agent type, model, effort, or the agent id if you would message one), and the
full prompt you would send.
