# galdr: hooks and status line

The `galdr` plugin holds seven Claude Code hooks and a status line. Install it
from the galdr marketplace:

```text
/plugin marketplace add nemesis398/galdr
/plugin install galdr@galdr
```

The scripts came from ravnix's `claude/hooks` and `claude/statusline` at
commit `6ab7115`, with the config and state paths moved to galdr's.

## The hooks

`hooks/hooks.json` wires each script as
`bash "${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh"`, quoted, so a plugin root with
a space in its path works.

| Event | Hook | Timeout | Does |
| --- | --- | --- | --- |
| SessionStart | `prune-claude-tmp` | 30 s | deletes the `/tmp/claude-<uid>` folders of sessions that have ended |
| SessionStart | `session-preflight` | 10 s | warns of Nextcloud conflicted copies and a NetBird mesh that is or goes down |
| SessionStart | `ssh-sockets` | 10 s | caches the control socket path of each SSH host in `statusline.sshHosts`, for the status line |
| PreToolUse, matcher `WebSearch` | `web-route` | 5 s | sends WebSearch to `searx` while SearXNG answers |
| PostToolUse, matcher `Edit\|Write` | `plan-track` | 5 s | records the plan file a session edits, for the status line |
| WorktreeCreate | `worktree-create` | 600 s | creates and provisions the worktree: ignored files, dependencies, the repository's setup |
| WorktreeRemove | `worktree-remove` | 60 s | runs the repository's teardown, removes the worktree, and its branch when that is safe |
| SubagentStop | `worktree-subagent-stop` | 30 s | sweeps idle subagent worktrees, which Claude Code never removes |

Each script's header says why it exists and what it does in each case.
`jq`, `curl`, `git`, `netbird`, `ssh`, `pnpm`, `npm` and `uv` come from your PATH.
The hooks run on Linux and on macOS, where they need Homebrew's bash 4.4 or
newer first in PATH; Homebrew's `coreutils` is optional. Under macOS's own
bash 3.2 each hook exits at once without a word, except `worktree-create`
and `worktree-remove`, which fail naming the bash they need. `prune-claude-tmp` prunes only
where `/proc` is, so on macOS it does nothing.
`searx` is an optional command-line client for a SearXNG instance (ravnix ships
one as packages/searx). A hook whose tool is missing stays silent, except
`worktree-create`: a lockfile whose tool is missing makes the worktree fail.
No hook fails a session: each one exits 0 whatever happens, except the two
worktree hooks, `worktree-create` and `worktree-remove`, whose failure is the
worktree's.

If the same hooks are also wired in your own settings, remove those entries
when you install the plugin, or each hook runs twice.

## The status line

A plugin cannot set the `statusLine` setting, so you wire it yourself. Point
the command at `statusline/statusline.sh` in the plugin's install directory,
`~/.claude/plugins/cache/galdr/galdr/<version>/`, and make the script the whole command, so
the shell execs it and the script sees the `claude` process as its parent:

```json
"statusLine": {
  "type": "command",
  "command": "bash /path/to/galdr/statusline/statusline.sh",
  "padding": 0,
  "refreshInterval": 60
}
```

The install directory carries the plugin's version, so the path changes with
an update. A stale path blanks the status line without an
error. A symbolic link at a fixed path, renewed after an update, keeps the
setting stable.

The status line prints two lines, each part only when its data exists, and
a line with no part is not printed. Line 1 is the budget: model and effort,
context, the 5h and weekly limits, the cache age, credits. Line 2 is place
and work: `[host · ][bg <id8> · ]<project> [↳ <dir>] · <branch> [wt] · plan <name> <n>% · 🔑 <label> ✓|✗ ...`. The
project is `workspace.project_dir` with `$HOME` shown as `~`. `↳` follows
when the current directory is below it (its relative path) or outside it
(its own path). The branch is read from `.git/HEAD` (a short sha when
detached, `wt` in a linked worktree), and nothing prints outside a
repository. The session id (first 8 characters) shows only next to `bg`.

The plan is the `*.md` file directly in `plans.dir` that the session last
edited with Edit or Write, as the `plan-track` hook recorded it. Its name
drops `.md` and a leading `YYYY-MM-DD-`, so `2026-11-22-galdr.md` prints as
`galdr`. The percentage is the frontmatter's `progress:`, and `status: done`
prints `✓` instead. A plan that was moved or deleted, or has no frontmatter,
prints no part, and so does a session without `plans.dir`.

The key shows whether the SSH masters in `statusline.sshHosts` still hold:
`🔑 forgejo ✓ github ✗` prints `✓` for a label whose control socket exists
and a yellow `✗` for one whose socket is gone. The `ssh-sockets` hook asks
`ssh -G` for each host's `ControlPath` at the start of a session; `ssh -G`
reads the SSH config and connects nowhere. A host without a `ControlPath`
is left out. A label prints only when it is both in the config and in that
cache, so a cache from an old config shows nothing. Before the hook has run
once, there is no part.

Three warnings follow, each only when it applies. `⚠ <hint>` shows when a
name in `statusline.requiredEnv` is missing from the environment of the
`claude` process (the hint is `statusline.requiredEnvHint`, else `env`).
`⚠ <n> sessions here` counts the other `claude` processes whose working
directory is the project. `⚠ /tmp <n>%` shows from 70% (red from 90%) of
the filesystem under `statusline.tmp.path`, or of `statusline.tmp.shareBytes`
when that is set. The first two read `/proc` and are off without it, as on
macOS. The disk figure comes from `df -Pk`, run at most every 300 s and
cached in `${XDG_STATE_HOME:-~/.local/state}/galdr/tmp-usage`, which is the
one process the status line starts besides `jq`. The cache needs the galdr
state directory, which the hooks make: while it is missing, `df` runs on
every refresh.

## The config file

The hooks and the status line read their values from one JSON file:
`GALDR_CONFIG` names it, else `${XDG_CONFIG_HOME:-~/.config}/galdr/config.json`.
It holds values only, never a secret.

A file that is missing, empty or not JSON sets nothing. A key that is
missing, or not of its type, counts as not set. Each script then turns its
part off and fails in no other way.

| Key | Type | Read by | Without it |
| --- | --- | --- | --- |
| `web.searxngUrl` | string, a URL | `web-route.sh` | WebSearch is never routed. `SEARXNG_URL` wins over the key |
| `nextcloud.root` | string, an absolute path | `session-preflight.sh` | no scan for conflicted copies. `PREFLIGHT_NEXTCLOUD_ROOT` wins over the key |
| `vault.root` | string, an absolute path inside `nextcloud.root` | `session-preflight.sh` | the vault's copies are counted under their folder, without the vault's rule |
| `vault.rule` | string, a sentence or two | `session-preflight.sh` | the vault's rule is to change nothing in it without the user's go-ahead |
| `netbird.managementUrl` | string, a URL | `session-preflight.sh` | no server counts as the wrong one, and a NeedsLogin names none |
| `netbird.whenDown` | string, one sentence | `session-preflight.sh` | the NetBird warnings do not say what fails while the mesh is down |
| `statusline.quietHosts` | list of host names, without a domain | `statusline.sh` | every host shows its tag |
| `plans.dir` | string, an absolute path | `plan-track.sh` | no plan is recorded, and the status line shows none |
| `statusline.sshHosts` | object, a label to an SSH host as `ssh` takes it | `ssh-sockets.sh`, `statusline.sh` | no SSH master is watched. A label or host that is empty or holds a control character, and a host that starts with `-`, is left out |
| `statusline.requiredEnv` | list of variable names | `statusline.sh` | no environment check. Needs `/proc` |
| `statusline.requiredEnvHint` | string, a few words | `statusline.sh` | the warning says `env` |
| `statusline.tmp.path` | string, an absolute path | `statusline.sh` | `/tmp` |
| `statusline.tmp.shareBytes` | number of bytes | `statusline.sh` | the size of the filesystem |

For example:

```json
{
  "web": { "searxngUrl": "https://search.example.org" },
  "nextcloud": { "root": "/home/alice/Nextcloud" },
  "vault": {
    "root": "/home/alice/Nextcloud/Notes",
    "rule": "Delete a note only with the vault's own tool, never with rm."
  },
  "netbird": {
    "managementUrl": "https://netbird.example.org:443",
    "whenDown": "While the mesh is down, the deploy server refuses every request."
  },
  "statusline": {
    "quietHosts": ["laptop"],
    "sshHosts": { "forgejo": "git.example.org", "github": "github.com" }
  },
  "plans": { "dir": "/home/alice/Nextcloud/Notes/plans" }
}
```

## State

The logs go under `${XDG_STATE_HOME:-~/.local/state}/galdr/`:
`prune-claude-tmp.log` and `worktree-hooks.log`. `plan-track` writes one
file per session to `galdr/plan/<session id>`, holding the plan's path, and
deletes the ones older than 30 days. `ssh-sockets` writes
`galdr/ssh-sockets`, one `<label>\t<socket path>` line per watched host. One
file stays outside it:
`web-route` caches whether SearXNG answers in
`${XDG_STATE_HOME:-~/.local/state}/web-route/reachable`, because `searx`
writes the same file when a search fails, and that is how a failed search
lets WebSearch through for the next minute.

## Tests

Each script has a test beside it, run with bash and no arguments:

```sh
for t in plugins/galdr/*/tests/*.test.sh; do bash "$t" || echo "FAIL $t"; done
```

The hook tests run each case three times: with the GNU tools, as macOS
without `coreutils` (BSD `stat` and `date`, no `timeout`, `setsid` or
`flock`), and as macOS with it; `tests/lib/bsd-shims.sh` plays the two Macs.
The exception is `prune-claude-tmp.test.sh`: it runs each case once, on
Linux only, plus one case under the BSD shims. It needs unprivileged user
namespaces there, and skips elsewhere;
`web-route.test.sh` needs `python3` for its fake server.
