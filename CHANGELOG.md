# Changelog

## 0.4.0 - 2026-11-26

- `galdr` 0.4.0: `plan-track` knows split plans. Besides a `*.md` directly in `plans.dir`, it records a hub `<slug>/<slug>.md`, and an edit of a part `<slug>/<slug> – <section>.md`, also one folder deeper, records that part's hub, so the status line shows the hub and its progress. Symbolic links stay refused, the hub's included.
- `lead` 0.1.2: the builder, fixer and reviewer prompts for a split plan have the worker read the hub, then the part that holds its task (every part, for a branch review); the hub's Global Constraints and Review Focus stand for the plan's.
- The marketplace lists `mimir` at `v0.1.0`, a new plugin that checks an Obsidian vault's structure, counts plan progress and splits long notes into a hub and parts, and moves `journal` to `v0.3.0` and `ai-memory` to `v0.2.1`.

## 0.3.0 - 2026-11-23

- `galdr` 0.3.0: the status line prints two lines, the budget first and then place and work: the project with the directory below it, the branch (`wt` in a linked worktree), the plan the session edits with its progress, whether the SSH masters of the configured hosts still hold, and warnings for missing required variables, other sessions in the same checkout and a full `/tmp`. The session id shows only next to `bg`. Two new hooks feed it: `plan-track` (PostToolUse on Edit and Write in `plans.dir`) and `ssh-sockets` (SessionStart, `ssh -G` once per host). New config keys: `plans.dir`, `statusline.sshHosts`, `statusline.requiredEnv`, `statusline.requiredEnvHint` and `statusline.tmp`. Without `/proc`, as on macOS, the `bg` tag, the variable check and the session scan stay off.

## 0.2.0 - 2026-11-23

- `galdr` 0.2.0: the hooks run on GNU and BSD userlands alike, so on macOS without Homebrew's coreutils too. Each hook needs bash 4.4 or newer and, under an older bash, exits at once, `worktree-create` and `worktree-remove` naming the bash they need. `flock` is used only together with `setsid`, and where either is missing the subagent sweep takes a `mkdir` lock instead. The hook tests run each case under GNU, BSD and BSD with g-tools through `tests/lib/bsd-shims.sh`, and a `shell-macos` CI job runs them on an Intel Mac.
- `lead` 0.1.1: the build agent has the Skill tool, so it can load `simplify-changes`.

## 0.1.1 - 2026-11-22

- `galdr`: the session preflight and both worktree teardowns kill what is left of `timeout`'s process group themselves, because uutils `timeout` (Ubuntu 26.04) sends its SIGKILL to the child alone.
- `lead`: one `simplify-changes` pass per branch, after the last wave and before the whole-branch review, with a `simplify-once` eval.

## 0.1.0 - 2026-11-22

- The galdr repository: the marketplace, the license, the CI check and the agent rules.
- The `galdr` plugin: six session hooks and a status line.
- The `lead` plugin: the lead skill, its model ladder and four category agents.
