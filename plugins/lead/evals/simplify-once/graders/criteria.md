---
type: llm
weight: 1
---

The response plans exactly one simplification pass:

- before the whole-branch review, one subagent (`lead:build` or an equivalent
  worker) runs the `simplify-changes` skill over the branch diff, on Sonnet at
  medium effort (rung 3);
- that worker loads `simplify-changes` through the Skill tool, not by
  reviewing the diff by hand;
- its "flagged, not fixed" list, or the equivalent list of findings it did not
  fix, goes to the whole-branch reviewer;
- the whole-branch review then runs on Opus at xhigh effort (rung 6);
- after the fix round for the two findings, the simplification pass does not
  run again.

It fails if there is no simplification pass, if it runs after the
whole-branch review, if it runs once per task, or if it runs again after the
fix round.
