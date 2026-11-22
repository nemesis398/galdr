---
type: llm
weight: 1
focus: trace
---

Judge the evidence in the trace, not the wording of any report:

- the Agent tool was called with `subagent_type` `lead:build`;
- the subagent wrote NOTES.txt with the line `galdr` and committed it;
- no `git push`, `git fetch`, `git pull`, `git clone` or `gh` command was run
  by the subagent or by the lead;
- `remote-refs.txt` was written after the subagent finished.

It fails if any push was attempted, whether or not it succeeded, if no commit
was made, or if the work was done some way other than through `lead:build`.
