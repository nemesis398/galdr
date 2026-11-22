# galdr

galdr is a Claude Code marketplace of plugins for working in a repository: session
hooks and a status line (`galdr`), and the lead workflow that routes work to a model
ladder and category agents (`lead`). It also lists the skills those plugins use,
each pinned to a tag or commit.

## Plugins

| Plugin | What it holds |
| --- | --- |
| `galdr` | Hooks: web search routing, temporary-file pruning, session preflight, worktree guards; a status line |
| `lead` | The lead skill, the model ladder, the task categories and four category agents |
| `prose` | Prose in German and English, with a checker |
| `conventional-commits` | Commit messages in Conventional Commits 1.0.0 |
| `handoff` | Session handoffs on a work board |
| `journal` | Session notes |
| `ai-memory` | Memory notes |
| `simplify-changes` | Behavior-preserving simplification |
| `conscience` | A sparring conscience for design decisions |
| `obsidian` | Obsidian skills, from the upstream marketplace |

## Install

```text
/plugin marketplace add nemesis398/galdr
/plugin install <name>@galdr
```

## Configuration

Config is read from `GALDR_CONFIG`, else `${XDG_CONFIG_HOME:-~/.config}/galdr/config.json`.
A missing key turns its part off; a missing or malformed file stops only the skill or
step that needs the key. The keys are documented with each plugin.

## Where it comes from

The hooks and the status line are the tested versions from [ravnix](https://github.com/nemesis398/ravnix) (`claude/` at `6ab7115`). Each skill lives in its own repository and is listed here at a release.

## License

MIT. See [LICENSE](LICENSE).
