# Changelog

## Unreleased

## 0.1.1 - 2026-11-22

- `galdr`: the session preflight and both worktree teardowns kill what is left of `timeout`'s process group themselves, because uutils `timeout` (Ubuntu 26.04) sends its SIGKILL to the child alone.
- `lead`: one `simplify-changes` pass per branch, after the last wave and before the whole-branch review, with a `simplify-once` eval.

## 0.1.0 - 2026-11-22

- The galdr repository: the marketplace, the license, the CI check and the agent rules.
- The `galdr` plugin: six session hooks and a status line.
- The `lead` plugin: the lead skill, its model ladder and four category agents.
