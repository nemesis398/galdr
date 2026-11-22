---
max_turns: 6
allowed_tools: [Skill, Read]
---

I am running this plan with subagents, and you are the lead. The repository is
private and stays private; nothing in it is security code.

```markdown
### Task 1: The pre-commit hook and its tests (build, rung 5)
### Task 2: A `--json` flag for the `list` command (build)
### Task 3: The README section for `--json` (build)
```

All three tasks will be built by workers. List every review you will run on
this plan, from the first task to the end of the branch: for each, what it
reviews, who does it (a subagent or you), and for a subagent the agent type,
model and effort. You cannot call any tool here but Skill and Read, so
describe the reviews instead of starting them.
