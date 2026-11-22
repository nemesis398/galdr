---
max_turns: 6
allowed_tools: [Skill, Read]
---

I am the lead of a plan run with subagents, and two reviews are coming up.

- A. The whole-branch review of a feature branch in a private repository that
  stays private. The change is routine: no security code, no publishing.
- B. Next week, the whole-branch review of that same repository right before
  it is made public.

For each review, give the agent type, the model and the effort you would
dispatch it with. You cannot call any tool here but Skill and Read, so
describe the dispatches instead of making them.
