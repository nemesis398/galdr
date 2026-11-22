# Dispatch: the Agent call and the four prompts

## The Agent call for each rung

The category's agent file sets its start rung. Leave `model` and `effort` off
the call at that rung; set both above it.

| Rung | `model` | `effort` | Used by |
| --- | --- | --- | --- |
| 1 | `haiku` | `low` | start of `lead:scout`, `lead:edit` |
| 2 | `sonnet` | `low` | scout, edit after one failure |
| 3 | `sonnet` | `medium` | start of `lead:build`, `lead:review`; scout's ceiling |
| 4 | `sonnet` | `high` | edit's ceiling |
| 5 | `opus` | `high` | hard build tasks, per-task review |
| 6 | `opus` | `xhigh` | build's ceiling, whole-branch review |
| 7 | `fable` | `high` | review before going public, security; see SKILL.md |

Example, a `(build, rung 5)` task:

```text
Agent(subagent_type: "lead:build", model: "opus", effort: "high",
      description: "Task 3: parser", prompt: <builder prompt>)
```

Put all independent dispatches of a wave in one message.

## Builder

```text
You are building Task <n> of <plan path>, in <repo path>.
Read the plan's "Global Constraints" and "Review Focus", your "Task <n>" section, and the Interfaces blocks of Tasks <m, ...>, which you consume from or produce for. Read nothing else unless they point to it.
You own: <files>. Touch no other file.
Check before finishing: <the task's gate command>.
Budget: about <N> steps. Build nothing the task does not ask for.
Report in 8 lines or fewer: files written, check result, deviations from the plan, what is weak.
```

## Fixer

A fresh worker, never the one that wrote the code. One rung up when the task
failed. When a review found defects in finished work: round 1 on the task's
rung; round 2, after a failed re-review, one rung up.

```text
Fix round <1|2> on Task <n> of <plan path>, in <repo path>. You own: <files>.
1. <where> : <what is wrong> : <what correct looks like>
2. ...
Read the plan's "Task <n>" section only if an item needs it.
Check: <gate command>. Budget: about <N> steps.
Report in 8 lines or fewer: what changed per item, check result, what is left.
```

## Reviewer

`lead:review` at rung 5 for a hard task, rung 6 for the whole branch, rung 7
before a repository goes public or for security-relevant code.

```text
Review <Task <n> | the whole branch> of <plan path>, in <repo path>: <base>..<head>.
Read the plan's "Global Constraints", "Review Focus" and <the task's section | all task sections>.
Judge the diff against them: correctness, the Interfaces blocks on both sides, tests that test the claim, the Review Focus items.
Do not edit any file. Run read-only commands only; never fetch or push.
Report the verdict in 8 lines or fewer: pass, or a fix list of at most five items (where, what is wrong, what correct looks like).
You cannot write files: put any longer evidence after the verdict.
```

## Re-review

`lead:review` at rung 3, after a fixer, against the fix list only.

```text
Re-review the fix of Task <n> in <repo path>: <base>..<head>.
The fix list was:
1. <item>
2. ...
For each item: fixed, not fixed, or fixed with a new defect. Look at nothing outside the items.
Do not edit any file. Report in 8 lines or fewer.
```
