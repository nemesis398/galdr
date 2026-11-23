#!/usr/bin/env bash
# ssh-sockets.sh: SessionStart hook (the plugin's README). For each SSH host
# the status line watches, it caches the path of the host's control socket,
# so the status line can show whether the SSH master still holds.
#
# Why: a session that pushes over SSH with a hardware key needs the master
# connection the user opened by hand, with a touch of the key. When it has
# gone, the next push waits on a key nobody is watching. The status line
# shows that with a test for a socket (-S, a builtin), but it may start no
# process but jq, and the socket's path is ssh's to work out: ControlPath,
# its %-tokens and Match blocks all live in the SSH config. So this hook asks
# ssh once per session, and the status line reads the answer with `read`.
#
# The hosts come from the config key statusline.sshHosts, an object of
# label to host, read from the file GALDR_CONFIG names, else from
# ${XDG_CONFIG_HOME:-~/.config}/galdr/config.json. Without the key, or with
# no usable entry, nothing is written. For each entry the hook runs
#
#   ssh -G -- <host> </dev/null
#
# and keeps the controlpath line. The cache is one line per label, in config
# order, `<label>\t<socket path>`, in
#
#   ${XDG_STATE_HOME:-~/.local/state}/galdr/ssh-sockets
#
# written to a temp file in the same directory and moved over the old one,
# so the status line never reads half a file. A host whose ssh fails, or
# whose control path is missing, `none` or not absolute, is left out.
#
# The labels and hosts are not trusted. A label or a host that is empty or
# holds a control character (a tab and a newline among them) is left out, so
# nothing in the config can split a cache line or reach the terminal. A host
# that starts with - is left out too, and the host reaches ssh as one
# argument after --, so no host can become an option.
#
# Why there is no watchdog: ssh -G prints the configuration and exits. It
# opens no connection and asks no key. Only two things in an SSH config can
# make it wait: a Match exec command and CanonicalizeHostname, which looks
# the name up in DNS. All hosts run at once, so a slow one costs its own
# time and not the sum. Should one hang, the hook's 10 s timeout ends it,
# and the old cache stays, since it is only replaced at the end. A kill of
# its own could not do better without timeout(1), which macOS lacks, or
# wait -n: it would signal the PID of a host that had already exited and
# been reaped, which the system may have given to another process.
#
# Fails open on everything: no ssh, no jq, a config that does not parse, an
# unwritable state directory. It prints nothing and exits 0, and below bash 4
# it does nothing.
#
# Tests: tests/ssh-sockets.test.sh, run with bash and no arguments.

[ "${BASH_VERSINFO[0]:-0}" -ge 4 ] 2>/dev/null || exit 0
command -v jq >/dev/null || exit 0
command -v ssh >/dev/null || exit 0

state=${XDG_STATE_HOME:-${HOME:-/nonexistent}/.local/state}/galdr
[[ $state == /* ]] || exit 0
values=${GALDR_CONFIG:-${XDG_CONFIG_HOME:-${HOME:-/nonexistent}/.config}/galdr/config.json}
[[ -f $values && -r $values ]] || exit 0

# One line per usable entry, label and host joined by a tab, which neither
# can hold. The jq variable $values must reach jq unexpanded.
# shellcheck disable=SC2016
prog='
($values | try fromjson catch null)
| objects | .statusline? | objects | .sshHosts? | objects | to_entries[]
| select((.key | test("^[^[:cntrl:]]+$"))
    and (.value | type) == "string" and (.value | test("^[^-[:cntrl:]][^[:cntrl:]]*$")))
| "\(.key)\t\(.value)"'
mapfile -t entries < <(jq -nr --rawfile values "$values" "$prog" 2>/dev/null)
((${#entries[@]})) || exit 0

work=$state/.ssh-sockets.$$
{ [[ -d $state ]] || mkdir -p -- "$state"; } 2>/dev/null || exit 0
mkdir -- "$work" 2>/dev/null || exit 0

# All hosts at once, each into its own file.
pids=()
for i in "${!entries[@]}"; do
    ssh -G -- "${entries[i]#*$'\t'}" </dev/null >"$work/$i" 2>/dev/null &
    pids[i]=$!
done

cache=""
for i in "${!entries[@]}"; do
    wait "${pids[i]}" || continue
    path=""
    while read -r key val; do
        [[ $key == controlpath ]] && path=$val
    done 2>/dev/null <"$work/$i"
    [[ $path == /* && $path != *[[:cntrl:]]* ]] || continue
    cache+=${entries[i]%%$'\t'*}$'\t'$path$'\n'
done

tmp=$state/.ssh-sockets.tmp.$$
if { printf '%s' "$cache" >"$tmp"; } 2>/dev/null; then
    mv -f -- "$tmp" "$state/ssh-sockets" 2>/dev/null
fi
rm -rf -- "$tmp" "$work" 2>/dev/null
exit 0
