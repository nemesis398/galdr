#!/usr/bin/env bash
# plan-track.sh: PostToolUse hook for Edit and Write (the plugin's README;
# hooks.json wires it with the matcher "Edit|Write"). When a session edits a
# plan, it records which one, so the status line can print the plan and its
# progress next to the branch.
#
# Why: a long session drifts from plan to plan, and the frontmatter's
# progress is what says how far the current one is. The status line runs
# after every message and may start no process but jq, so it cannot search
# the transcript for the plan. This hook writes the answer where the status
# line reads it with `read`.
#
# A plan is a *.md file directly in the directory the config key plans.dir
# names (an absolute path), read from the file GALDR_CONFIG names, else from
# ${XDG_CONFIG_HOME:-~/.config}/galdr/config.json. Without the key, nothing
# is recorded. A split plan is a folder in plans.dir: its hub is
# <slug>/<slug>.md, its parts are <slug>/<slug> – <section>.md, and a part
# split deeper is a folder <slug>/<slug> – <section>/ whose own notes are
# named after it the same way. An edit of the hub or of any of its parts
# records the hub, because the hub's progress counts all of them; a part
# whose hub is missing or a symbolic link records nothing. The record is one
# line, the plan's absolute path, in
#
#   ${XDG_STATE_HOME:-~/.local/state}/galdr/plan/<session id>
#
# written to a temp file in the same directory and moved over the old one,
# so the status line never reads half a line. Each write also deletes the
# state files that have not been written for 30 days: their sessions are
# long over.
#
# The session id and the file path come from the hook input and are not
# trusted. The id is cleaned to [A-Za-z0-9-], the way the status line cleans
# it, so the state file is always a plain name in galdr/plan/; an id with
# nothing left writes nothing. The path must be absolute, name an existing
# regular file that is no symbolic link, and its directory must be plans.dir,
# or a hub's folder in it, once both are resolved with `cd -P` (a builtin, so
# no readlink -f, which macOS lacks): `..`, a symlinked parent and a trailing
# slash all compare as the directories they lead to, so a hub folder that
# links outside plans.dir is no hub folder. A path or a plans.dir with a control
# character in it is no path. The path recorded is the resolved one.
#
# Fails open on everything: no jq, input or config that does not parse, an
# unwritable state directory. It prints nothing and exits 0, and below bash 4
# it does nothing.
#
# Tests: tests/plan-track.test.sh, run with bash and no arguments.

[ "${BASH_VERSINFO[0]:-0}" -ge 4 ] 2>/dev/null || exit 0
command -v jq >/dev/null || exit 0
unset CDPATH

state=${XDG_STATE_HOME:-${HOME:-/nonexistent}/.local/state}/galdr/plan
[[ $state == /* ]] || exit 0
values=${GALDR_CONFIG:-${XDG_CONFIG_HOME:-${HOME:-/nonexistent}/.config}/galdr/config.json}
[[ -f $values && -r $values ]] || values=/dev/null

# One line: the cleaned session id, the file path and plans.dir, each led by
# _ so an empty one keeps its place when read splits on the tabs. A path that
# is no string, or holds a control character (a tab among them), is empty.
# The jq variable $values must reach jq unexpanded.
# shellcheck disable=SC2016
prog='
def path: strings | select(test("[[:cntrl:]]") | not);
(try input catch null) as $in
| [($in | (.session_id? | strings) // "" | gsub("[^A-Za-z0-9-]"; "")),
   ($in | (.tool_input?.file_path? | path) // ""),
   (($values | try fromjson catch null) | (objects | .plans? | objects | .dir? | path) // "")]
| map("_" + .) | join("\t")'
IFS=$'\t' read -r sid file dir <<<"$(jq -nr --rawfile values "$values" "$prog" 2>/dev/null)"
sid=${sid#_} file=${file#_} dir=${dir#_}

[[ -n $sid && $file == /* && $dir == /* ]] || exit 0
base=${file##*/} parent=${file%/*}
[[ $base == ?*.md && -f $file && ! -L $file ]] || exit 0
cd -P -- "${parent:-/}" 2>/dev/null || exit 0
parent=$PWD
cd -P -- "$dir" 2>/dev/null || exit 0
dir=$PWD

# Directly in plans.dir, the file is the plan. One folder down, the folder
# is the hub's (slug is top); two down, it is a part's folder in the hub's,
# named "<top> – <section>". Either way the file is that folder's own note
# or one of its parts, and the plan is the hub.
if [[ $parent == "$dir" ]]; then
    plan=${parent%/}/$base
else
    slug=${parent##*/} up=${parent%/*}
    if [[ ${up:-/} == "$dir" ]]; then
        top=$slug hubdir=$parent
    else
        top=${up##*/} above=${up%/*}
        [[ ${above:-/} == "$dir" && $slug == "$top – "?* ]] || exit 0
        hubdir=$up
    fi
    [[ $base == "$slug.md" || $base == "$slug – "?*.md ]] || exit 0
    plan=$hubdir/$top.md
    [[ -f $plan && ! -L $plan ]] || exit 0
fi

# The braces come first so the shell's own "no such file" goes to /dev/null
# too: a redirection is opened before a later 2> takes effect.
tmp=$state/.$sid.$$
if { [[ -d $state ]] || mkdir -p -- "$state"; } 2>/dev/null \
    && { printf '%s\n' "$plan" >"$tmp"; } 2>/dev/null; then
    mv -f -- "$tmp" "$state/$sid" 2>/dev/null
    find "$state" -maxdepth 1 -type f -mtime +30 -delete 2>/dev/null
fi
rm -f -- "$tmp" 2>/dev/null
exit 0
