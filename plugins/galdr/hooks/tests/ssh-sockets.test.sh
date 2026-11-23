#!/usr/bin/env bash
# Tests for ssh-sockets.sh, one directory up: the SessionStart hook that
# caches the control socket path of each SSH host the status line watches.
#
# Why these cases: the labels and hosts come from the config, and the hook
# hands each host to ssh and writes each label into a file the status line
# prints from. So cases feed it a host that starts with -, a host with a
# space, labels with a tab, a newline and an escape in them, and values of
# the wrong type, and check what reaches ssh and what reaches the cache.
# Two slow hosts check that the hook asks ssh for all hosts at once.
#
# No case runs the real ssh. A fake ssh on PATH logs its arguments, one per
# line, each call in a file of its own, so calls that run at once cannot mix
# their lines. It prints `controlpath /x/cm-<host>` for an ordinary host.
# Some hosts make it behave otherwise:
#   nocp.example.org  no controlpath line
#   none.example.org  controlpath none
#   cc.example.org    a controlpath with an escape in it
#   fail.example.org  exit 255, as ssh does on a broken config
#   slow*.example.org takes about 1 s, then answers as an ordinary host
# The hook runs with a PATH of links to the tools it may use, plus the fake,
# and nothing else. HOME and XDG_STATE_HOME point into the sandbox, and the
# config comes from GALDR_CONFIG, so the user's own state, config and SSH
# config are never read.
#
# Run:  bash ssh-sockets.test.sh          (exit 0 = all green)
# SSH_SOCKETS_UNDER_TEST=<file> tests another copy, for mutation runs.
# The sandbox lives under ${TMPDIR:-/tmp} and is removed on exit.

# The checks are eval'd, so their $ expand at check time, and the variables
# they read look unused to shellcheck.
# shellcheck disable=SC2016,SC2034

set -uo pipefail

# Paths are resolved with the cd -P builtin, not readlink -f, so the tests
# run on macOS too, where /tmp and /var/folders are links into /private.
case $0 in */*) here=${0%/*} ;; *) here=. ;; esac
HERE=$(cd -P -- "$here" && pwd -P) || { echo "cannot resolve $0" >&2; exit 2; }
HOOK=${SSH_SOCKETS_UNDER_TEST:-${HERE%/*}/ssh-sockets.sh}
HOOK=$(cd -P -- "${HOOK%/*}" 2>/dev/null && pwd -P)/${HOOK##*/}
[ -f "$HOOK" ] || { echo "missing $HOOK" >&2; exit 2; }

SB=$(mktemp -d "${TMPDIR:-/tmp}/ssh-sockets-test.XXXXXX")
SB=$(cd -P -- "$SB" && pwd -P)
trap 'rm -rf -- "$SB"' EXIT

pass=0 fail=0
ok()  { printf '  \e[32m✓\e[0m %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  \e[31m✗\e[0m %s\n%s\n' "$1" "$2"; fail=$((fail + 1)); }

# --- the sandbox -----------------------------------------------------------

SYS=$SB/sys NOJQ=$SB/nojq FAKE=$SB/fake
mkdir -p "$SYS" "$NOJQ" "$FAKE" "$SB/home"
for t in bash jq mkdir mv rm sleep; do
    p=$(type -P "$t") || { echo "the tests need $t, which is not installed" >&2; exit 2; }
    ln -s "$p" "$SYS/$t"
    [[ $t == jq ]] || ln -s "$p" "$NOJQ/$t"
done

LOG=$SB/ssh.d
cat >"$FAKE/ssh" <<EOF
#!$BASH
# One new file per call: noclobber makes > fail on a name already taken.
set -C
until f=$LOG/\$\$.\$RANDOM; { printf '%s\n' "\$@" >"\$f"; } 2>/dev/null; do :; done
set +C
host=\${!#}
case \$host in
    nocp.example.org) printf 'user u\n' ;;
    none.example.org) printf 'controlpath none\n' ;;
    cc.example.org) printf 'controlpath /x/a\033b\n' ;;
    fail.example.org) exit 255 ;;
    slow*.example.org) sleep 1
        printf 'controlpath /x/cm-%s\n' "\$host" ;;
    *) printf 'user u\nhostname %s\ncontrolpath /x/cm-%s\nport 22\n' "\$host" "\$host" ;;
esac
EOF
chmod +x "$FAKE/ssh"

CACHE=$SB/state/galdr/ssh-sockets

# config <json>: the config file the next runs read.
config() { printf '%s\n' "$1" >"$SB/config.json"; }

# run [ENV=VAL ...]: the hook with the sandbox environment and a
# SessionStart input on stdin. Sets $out, $err, $rc and $took (milliseconds).
# EPOCHREALTIME's separator follows the locale, so only its digits count.
now_ms() { local t=${EPOCHREALTIME//[!0-9]/}; printf '%s' "$((10#${t:0:-3}))"; }
run() {
    local t0
    t0=$(now_ms)
    out=$(printf '{"session_id":"abc","hook_event_name":"SessionStart","source":"startup"}' \
        | env -i HOME="$SB/home" PATH="$FAKE:$SYS" \
        XDG_STATE_HOME="$SB/state" GALDR_CONFIG="$SB/config.json" \
        "$@" bash "$HOOK" 2>"$SB/err")
    rc=$?
    took=$(($(now_ms) - t0))
    err=$(<"$SB/err")
}
reset() { rm -rf -- "$SB/state" "$LOG" && mkdir -- "$LOG"; }
cached() { [[ -f $CACHE ]] && cmp -s "$CACHE" <(printf '%s' "$1"); }
nofile() { [[ ! -e $CACHE ]]; }
silent() { [[ $rc == 0 && -z $out && -z $err ]]; }
# called <arg>...: some call of the fake ssh had exactly these arguments.
called() {
    local want f
    want=$(printf '%s\n' "$@")
    for f in "$LOG"/*; do [[ -f $f && $(<"$f") == "$want" ]] && return 0; done
    return 1
}
# calls: how many times the fake ssh ran.
calls() { local f=("$LOG"/*); [[ -e ${f[0]} ]] && printf '%s' "${#f[@]}" || printf 0; }
# calls_seen: every call's arguments, one call per line, for a failing check.
calls_seen() { local f; for f in "$LOG"/*; do [[ -f $f ]] && printf '[%s] ' "$(tr '\n' ' ' <"$f")"; done; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "    rc: $rc
    out: $out
    err: $err
    cache: $(cat -A "$CACHE" 2>/dev/null)
    took: $took ms
    ssh: $(calls_seen)"; fi; }

echo "ssh-sockets"

# --- the cache -------------------------------------------------------------

reset
config '{"statusline":{"sshHosts":{"forgejo":"git.example.org","github":"github.com"}}}'
run
check "writes both labels, in config order, with their control paths" \
    'silent && cached $'"'"'forgejo\t/x/cm-git.example.org\ngithub\t/x/cm-github.com\n'"'"
check "ssh gets -G, --, and the host, and nothing else" \
    'called -G -- git.example.org && called -G -- github.com && [[ $(calls) == 2 ]]'
check "no temp file stays behind" '[[ $(ls -A "$SB/state/galdr") == ssh-sockets ]]'

config '{"statusline":{"sshHosts":{"github":"github.com"}}}'
run
check "a later run replaces the cache whole" 'silent && cached $'"'"'github\t/x/cm-github.com\n'"'"

reset
config '{"statusline":{"sshHosts":{"a":"nocp.example.org","b":"none.example.org","c":"github.com"}}}'
run
check "skips a host without controlpath, and one whose controlpath is none" \
    'silent && cached $'"'"'c\t/x/cm-github.com\n'"'"

reset
config '{"statusline":{"sshHosts":{"a":"nocp.example.org"}}}'
run
check "no host with a control path leaves an empty cache" 'silent && cached ""'

reset
config '{"statusline":{"sshHosts":{"a":"cc.example.org","b":"fail.example.org","c":"github.com"}}}'
run
check "skips a control path with an escape in it, and a host whose ssh fails" \
    'silent && cached $'"'"'c\t/x/cm-github.com\n'"'"

# --- untrusted labels and hosts --------------------------------------------

reset
config '{"statusline":{"sshHosts":{"evil":"-oProxyCommand=touch /tmp/x","dash":"-","ok":"github.com"}}}'
run
check "a host starting with - never reaches ssh, and its label is left out" \
    'silent && cached $'"'"'ok\t/x/cm-github.com\n'"'"' && ! grep -rq "^-o\|^-$" "$LOG"'

reset
config '{"statusline":{"sshHosts":{"sp":"my host"}}}'
run
check "a host with a space reaches ssh as one argument" \
    'silent && called -G -- "my host" && cached $'"'"'sp\t/x/cm-my host\n'"'"

reset
config '{"statusline":{"sshHosts":{"a\tb":"github.com","c\nd":"github.com","e\u001b[2Jf":"github.com","":"github.com","ok":"github.com"}}}'
run
check "labels with a tab, a newline or an escape, and an empty one, are left out" \
    'silent && cached $'"'"'ok\t/x/cm-github.com\n'"'"

reset
config '{"statusline":{"sshHosts":{"a":"git\u001b.example.org","b":"git\n.example.org","c":"","d":42,"e":null,"ok":"github.com"}}}'
run
check "hosts with a control character, an empty one and non-strings are left out" \
    'silent && cached $'"'"'ok\t/x/cm-github.com\n'"'"' && [[ $(calls) == 1 ]]'

# --- no config, no file ----------------------------------------------------

for c in 'no key:{"statusline":{}}' 'an empty object:{"statusline":{"sshHosts":{}}}' \
    'a list:{"statusline":{"sshHosts":["github.com"]}}' 'an empty file:' 'not JSON:{"statusline":'; do
    reset
    config "${c#*:}"
    run
    check "no config, no file: ${c%%:*}" 'silent && nofile && [[ $(calls) == 0 ]]'
done
reset
run GALDR_CONFIG="$SB/no-such.json"
check "no config, no file: a missing config file" 'silent && nofile'
config '{"statusline":{"sshHosts":{"github":"github.com"}}}'

# --- failing open ----------------------------------------------------------

reset
run PATH="$SYS"
check "exit 0 without ssh, nothing written" 'silent && nofile'

reset
run PATH="$FAKE:$NOJQ"
check "exit 0 without jq, nothing written" 'silent && nofile'

reset
mkdir -p "$SB/state"
: >"$SB/state/galdr"
run
check "exit 0 when galdr/ cannot be made (a file is in its place)" \
    'silent && [[ -f $SB/state/galdr && ! -s $SB/state/galdr ]]'

reset
config '{"statusline":{"sshHosts":{"a":"slow1.example.org","b":"slow2.example.org"}}}'
run
check "two hosts of 1 s each take under 2 s: ssh runs for all at once" \
    'silent && ((took >= 1000 && took < 1950)) && [[ $(calls) == 2 ]] \
    && cached $'"'"'a\t/x/cm-slow1.example.org\nb\t/x/cm-slow2.example.org\n'"'"
# A TERM, as the hook timeout sends it, while ssh still runs: the hook
# removes its own work directory and temp file, and the old cache stays.
reset
mkdir -p "$SB/state/galdr"
printf 'old\t/x/old\n' >"$CACHE"
config '{"statusline":{"sshHosts":{"a":"slow1.example.org"}}}'
printf '{}' >"$SB/in"
env -i HOME="$SB/home" PATH="$FAKE:$SYS" XDG_STATE_HOME="$SB/state" \
    GALDR_CONFIG="$SB/config.json" bash "$HOOK" <"$SB/in" >"$SB/out" 2>"$SB/err" &
hook=$!
for _ in {1..100}; do [[ $(calls) == 0 ]] || break; sleep 0.02; done
kill -TERM "$hook" 2>/dev/null
wait "$hook"
rc=$? out=$(<"$SB/out") err=$(<"$SB/err") took=-
left=$(cd "$SB/state/galdr" && printf '%s ' .ssh-sockets.*)
check "a TERM while ssh runs leaves no .ssh-sockets.<pid> behind, and the old cache" \
    '[[ $(calls) == 1 && -z $out && -z $err && $left == ".ssh-sockets.* " ]] \
    && cached $'"'"'old\t/x/old\n'"'"' || { echo "    left: $left"; false; }'
config '{"statusline":{"sshHosts":{"github":"github.com"}}}'

# --- as hooks.json runs it -------------------------------------------------

PLUGIN=${HERE%/*/*}
mkdir -p "$SB/root space" && cp -r -- "$PLUGIN" "$SB/root space/galdr"
CMD=$(jq -r '.hooks.SessionStart[].hooks[] | select(.command | test("ssh-sockets")) | .command' "$PLUGIN/hooks/hooks.json")
TIMEOUT=$(jq -r '.hooks.SessionStart[].hooks[] | select(.command | test("ssh-sockets")) | .timeout' "$PLUGIN/hooks/hooks.json")
reset
out=$(printf '{}' | env -i HOME="$SB/home" PATH="$FAKE:$SYS" \
    XDG_STATE_HOME="$SB/state" GALDR_CONFIG="$SB/config.json" \
    CLAUDE_PLUGIN_ROOT="$SB/root space/galdr" bash -c "$CMD" 2>"$SB/err")
rc=$? err=$(<"$SB/err")
check "plugin-root-space: run as hooks.json writes it (SessionStart, 10 s), it caches" \
    'silent && [[ $CMD == *ssh-sockets.sh* && $TIMEOUT == 10 ]] && cached $'"'"'github\t/x/cm-github.com\n'"'"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
