# galdr: hooks and status line

The `galdr` plugin holds six Claude Code hooks and a status line. Install it
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
| PreToolUse, matcher `WebSearch` | `web-route` | 5 s | sends WebSearch to `searx` while SearXNG answers |
| WorktreeCreate | `worktree-create` | 600 s | creates and provisions the worktree: ignored files, dependencies, the repository's setup |
| WorktreeRemove | `worktree-remove` | 60 s | runs the repository's teardown, removes the worktree, and its branch when that is safe |
| SubagentStop | `worktree-subagent-stop` | 30 s | sweeps idle subagent worktrees, which Claude Code never removes |

Each script's header says why it exists and what it does in each case.
`jq`, `curl`, `git`, `netbird`, `pnpm`, `npm` and `uv` come from your PATH.
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
  "statusline": { "quietHosts": ["laptop"] }
}
```

## State

The logs go under `${XDG_STATE_HOME:-~/.local/state}/galdr/`:
`prune-claude-tmp.log` and `worktree-hooks.log`. One file stays outside it:
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
