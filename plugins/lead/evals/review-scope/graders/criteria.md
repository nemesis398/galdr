---
type: llm
weight: 1
---

The response plans exactly this review scope:

- Task 1 (a hard task, rung 5) gets a per-task review by a fresh reviewer
  subagent (`lead:review` or an equivalent reviewer) on Opus at high effort;
- Task 2 and Task 3 get no reviewer subagent of their own: the lead reads
  their diffs and checks that their gate or tests are green;
- one whole-branch review runs at the end, by a reviewer subagent on Opus at
  xhigh effort (rung 6).

Extra reviews that run only if a fix round happens (a re-review of a fix
diff) are fine, and so is retagging Task 3, as long as Task 2 and Task 3 get no
reviewer subagent of their own.

It fails if Task 2 or Task 3 gets its own reviewer subagent, if the whole-branch
review is missing, or if the whole-branch review runs on Fable or at rung 7.
