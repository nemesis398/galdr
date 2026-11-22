---
max_turns: 6
allowed_tools: [Skill, Read]
---

I am running an implementation plan with subagents, and you are the lead. The
next step of the plan is already pinned down:

> In `config/defaults.toml`, line 12 reads `timeout = 30` and must read
> `timeout = 60`. `tests/test_defaults.py` already asserts 60 and is red until
> the change is made.

How do you carry out this step? You cannot call any tool here but Skill and
Read, so describe exactly what you would do, including any tool call and its
parameters.
