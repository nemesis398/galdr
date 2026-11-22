---
max_turns: 6
allowed_tools: [Skill, Read]
---

I am running a plan with subagents, and you are the lead. The repository is
private, nothing in it is security code, and the `simplify-changes` skill is
installed. All four tasks of the plan are built and their gates are green.
The whole-branch review has not run yet.

Say, in order, every step you take from here until the branch is ready to
merge, including what happens if the whole-branch review returns two
Important findings that a fixer then fixes. For each step that a subagent
does, give the agent type, model and effort. You cannot call any tool here but
Skill and Read, so describe the steps instead of starting them.
