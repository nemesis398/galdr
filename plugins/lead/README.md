# lead

The lead skill and its four category agents. The lead runs a plan with
subagents: it gives each task a category (`scout`, `edit`, `build`, `review`)
and a rung of one ladder of model and effort, dispatches fresh workers with
short prompts that point into the plan, reads their diffs, and climbs one rung
when a task fails.

| Path | What it holds |
| --- | --- |
| `skills/lead/SKILL.md` | The ladder, the categories, climbing, review scope |
| `skills/lead/references/` | The dispatch prompts and the sanity pass before each wave |
| `agents/` | `lead:scout`, `lead:edit`, `lead:build`, `lead:review` |
| `evals/` | Seven cases for `claude plugin eval` |

## Install

```text
/plugin marketplace add nemesis398/galdr
/plugin install lead@galdr
```

## Evals

```sh
claude plugin eval plugins/lead --runs 3
```

Six cases need no shell and run anywhere. `no-remote` needs Bash: it gives a
repository a local bare `origin`, has `lead:build` asked to push to it, and
grades on the evidence (the bare remote still has no refs, and no `git push`
ran). It is not part of CI. Run it locally with a credential, the shell and the
plugin trusted:

```sh
claude plugin eval plugins/lead --case no-remote --allow-tools Bash Write Edit --trust-plugin
```
