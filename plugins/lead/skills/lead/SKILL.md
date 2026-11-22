---
name: lead
description: Run as the lead of a plan or job that subagents carry out, choosing for each task a category (scout, edit, build, review) and a rung of one ladder of model and effort, dispatching fresh workers with short prompts that point into the plan, reading their diffs, and climbing one rung when a task fails. Use this whenever a plan is being implemented with subagents, a subagent or implementer is about to be dispatched, subagent-driven development is running, work is being orchestrated or delegated, a model or effort level has to be picked for a subagent or a review, or the user wants to save tokens or cost with subagents, even if this skill is not named.
---

# Lead: the plan is the contract, the ladder sets the price

The lead is the most expensive agent in the run, because every request it
makes re-sends its whole context. Its tokens buy judgment: the plan, the
dispatch, the read of a diff. Workers buy volume: reading, writing, running.
The aim is the result a solo run would reach, for clearly less.

## The ladder

| Rung | Model | Effort |
| --- | --- | --- |
| 1 | Haiku | low |
| 2 | Sonnet | low |
| 3 | Sonnet | medium |
| 4 | Sonnet | high |
| 5 | Opus | high |
| 6 | Opus | xhigh |
| 7 | Fable | high |

## The four categories

Each category has one pinned agent whose file carries its start rung. A task
starts on that rung (or on its tag's higher rung) and never climbs past the
ceiling.

| Category | Agent | Start | Ceiling | Turns | For |
| --- | --- | --- | --- | --- | --- |
| scout | `lead:scout` | 1 | 3 | 20 | finding files, inventories, a map of at most 40 lines; docs, versions, comparisons, with the findings in a file |
| edit | `lead:edit` | 1 | 4 | 15 | mechanical work: a rename, copy and adapt, a config value, a template, one file of up to about 300 lines |
| build | `lead:build` | 3 | 6 | 50 | a plan task with tests and fixed interfaces; from rung 5 the hard ones: algorithms, parsers, concurrency, security, shared machinery (hooks, skills, shared scripts), root-cause debugging |
| review | `lead:review` | 3 | 7 | 40 | rung 3: a fix diff against its fix list; rung 5: a per-task review; rung 6: the whole-branch review; rung 7: the whole-branch review before a repository goes public, or of security-relevant code |

**Tags.** The plan's writer tags each task heading with its category and, when
the task needs more, a higher start rung: `(build)`, `(build, rung 5)`,
`(edit)`. An old `(opus)` reads as `(build, rung 5)`; a task without a tag is
`(build)`. A *hard task* is a build task that starts at rung 5 or higher. The
lead may correct a tag in the sanity pass and says so in the tick line.

**Dispatch.** At the start rung, call the category's agent with no `model` or
`effort`. Above it, set both on the Agent call from the ladder: `model` is
`haiku`, `sonnet`, `opus` or `fable`. The exact calls and the prompt shapes
are in `references/dispatch.md`.

## Climbing

A task has failed when its gate stays red after the worker stops, or when its
review fails twice. Then:

1. Write a fix list of at most five items: where, what is wrong, what correct
   looks like.
2. Dispatch a **fresh** worker of the same category **one rung up**, with the
   fix list. Never the same rung again, never a resumed worker.
3. At the category's ceiling the task comes back to the lead, which does it
   itself or asks the user. A build task that failed at rung 6 may go to
   Fable (rung 7) through the lead, as a deliberate call.

A defect found by a review of a finished task is not yet a failure: its fixer
is a fresh worker with the fix list. Round 1 on the task's rung; round 2, after
a failed re-review, one rung up. After that, the remaining weaknesses go to the
user in plain words.

A worker cut off at its turn budget may continue once on the same rung, by a
fresh worker, but only when its report says the work is unfinished but on
track: its files are on disk and no gate is red from its own work. The next
stop climbs.

## Fable

Fable is rung 7 and nothing else. It costs about twice Opus, and the lead is
already the largest share of a run, so it never leads and never builds by
default. It runs in three cases only:

- the whole-branch review before a repository goes public, or of
  security-relevant code;
- a build task that failed at rung 6, through the lead;
- a spec or design, when the user asks for Fable to write it.

A routine whole-branch review of a private repository is rung 6, Opus at
xhigh.

## The flow

1. **Sanity pass** before each wave (`references/sanity-pass.md`). Fix the
   plan's text, not the prompts: a ruling that lives only in the lead's head
   never reaches the worker.
2. **Dispatch the wave**: one Agent call per task, all independent tasks in one
   message. A prompt is about eight lines that point at the plan's Global
   Constraints, its Interfaces blocks and the task's own section. No per-task
   brief files, except the brief `dvergr run` needs, in the scratchpad.
3. **Wait.** A notification while other workers still run gets one line of
   acknowledgement, not a review.
4. **Read the diff, not the files**, and the gate's result. Then tick the
   plan's box with the evidence (commit, test count) and any ruling made.
5. **Review** as below, then the next wave.

## Review scope

- **A hard or security-relevant task** gets a fresh `lead:review` at rung 5
  after its gate is green.
- **Every other task** gets the lead's read of its diff plus the green gate,
  and no reviewer of its own.
- **A fix diff**, when a fixer's change needs a second pair of eyes, gets a
  re-review at rung 3 against its fix list only.
- **The whole branch** gets one `lead:review` at rung 6 on every branch, before
  the first push when that push publishes; rung 7 instead when the push makes
  the repository public or the branch holds security-relevant code.

Per-task reviews pass holes that the plan itself wrote in; the whole-branch
review is the one that catches them, so it is never skipped.

## When not to delegate

A worker carries tens of thousands of tokens of overhead before its first
step, and its prompt and report cost lead tokens too. Do it yourself when:

- the job fits in about a dozen tool calls;
- it is a one-line fix that is already pinned down;
- it touches a secret.

## Staying small

- Plan with searches, not by reading files. If planning needs more than about
  five files, send `lead:scout` for a map of at most 40 lines.
- After planning, read diffs and reports, not files.
- Batch independent tool calls in one message.
- Target: about 10 lead requests per task, from dispatch to tick.
- Never resume a finished worker with SendMessage. A fresh worker with a
  pointer into the plan starts at a fraction of the resumed one's context.
- One editor per file at a time: fixers and builders of one wave own disjoint
  files.
- When a task's acceptance needs a state that is slow to reach, the plan builds
  a state hook into the product: a flag, a seed, a URL parameter.
- Category agents never touch a remote. Pushes, fetches, clones and `gh` stay
  with the lead.

## dvergr

In a repository with `.dvergr.json`, a build task at rung 3 or 4 goes to a
dvergr worker with role `code`, and a hard task with role `hard`, unless it is
security-relevant. dvergr is a skill that routes implementer steps, if one is
installed (for example dvergr); it decides the rest.

## What stays from test-driven plans

- TDD where the plan writes it: failing test, run, implement, run.
- The plan's ticks carry the evidence. There is no extra ledger: the tick line
  holds the rulings.
- Opus for judgment: design, review, root-cause debugging and shared machinery
  start at rung 5. Haiku only where a wrong answer costs a cheap retry, with
  the ladder behind it.

## Precedence

`superpowers:subagent-driven-development` prescribes a reviewer after every
task and a brief file per task. Where it and this skill differ, the lead rules
here win: review scope as above, prompts that point into the plan. The user's
own instructions settle the order and win over both.

## References

- `references/dispatch.md`: the builder, fixer, reviewer and re-review prompts,
  and the Agent call for each rung.
- `references/sanity-pass.md`: the checks before each wave.
