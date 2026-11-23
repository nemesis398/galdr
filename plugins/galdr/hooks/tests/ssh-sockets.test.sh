#!/usr/bin/env bash
# Tests for ssh-sockets.sh, one directory up: the SessionStart hook that
# caches the control socket path of each SSH host the status line watches.
#
# Why these cases: the labels and hosts come from the config, and the hook
# hands each host to ssh and writes each label into a file the status line
# prints from. So cases feed it a host that starts with -, a host with a
# space, labels with a tab, a newline and an escape in them, and values of
# the wrong type, and check what reaches ssh and what reaches the cache.
# A host whose ssh never returns checks that the hook still ends well
# inside its 10 s timeout and keeps the other hosts.
#
# No case runs the real ssh. A fake ssh on PATH logs its arguments, one per
# line, and prints `controlpath /x/cm-<host>` for an ordinary host. Some
# hosts make it behave otherwise:
#   nocp.example.org  no controlpath line
#   none.example.org  controlpath none
#   cc.example.org    a controlpath with an escape in it
#   fail.example.org  exit 255, as ssh does on a broken config
#   hang.example.org  never returns
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

SELF=$(readlink -f "$0")
HOOK=${SSH_SOCKETS_UNDER_TEST:-${SELF%/*/*}/ssh-sockets.sh}
HOOK=$(readlink -f "$HOOK")
[ -f "$HOOK" ] || { echo "missing $HOOK" >&2; exit 2; }

SB=$(mktemp -d "${TMPDIR:-/tmp}/ssh-sockets-test.XXXXXX")
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

LOG=$SB/ssh.log
cat >"$FAKE/ssh" <<EOF
#!$BASH
{ printf '%s\n' "\$@"; printf '%s\n' --; } >>"$LOG"
host=\${!#}
case \$host in
    nocp.example.org) printf 'user u\n' ;;
    none.example.org) printf 'controlpath none\n' ;;
    cc.example.org) printf 'controlpath /x/a\033b\n' ;;
    fail.example.org) exit 255 ;;
    hang.example.org) exec sleep 30 ;;
    *) printf 'user u\nhostname %s\ncontrolpath /x/cm-%s\nport 22\n' "\$host" "\$host" ;;
esac
EOF
chmod +x "$FAKE/ssh"

CACHE=$SB/state/galdr/ssh-sockets

# config <json>: the config file the next runs read.
config() { printf '%s\n' "$1" >"$SB/config.json"; }

# run [ENV=VAL ...]: the hook with the sandbox environment and a
# SessionStart input on stdin. Sets $out, $err, $rc and $took (seconds).
run() {
    local t0=$SECONDS
    out=$(printf '{"session_id":"abc","hook_event_name":"SessionStart","source":"startup"}' \
        | env -i HOME="$SB/home" PATH="$FAKE:$SYS" \
        XDG_STATE_HOME="$SB/state" GALDR_CONFIG="$SB/config.json" \
        "$@" bash "$HOOK" 2>"$SB/err")
    rc=$?
    took=$((SECONDS - t0))
    err=$(<"$SB/err")
}
reset() { rm -rf -- "$SB/state" "$LOG"; }
cached() { [[ -f $CACHE ]] && cmp -s "$CACHE" <(printf '%s' "$1"); }
nofile() { [[ ! -e $CACHE ]]; }
silent() { [[ $rc == 0 && -z $out && -z $err ]]; }
# called <arg>...: the fake ssh saw exactly these arguments on some call.
called() { local want; want=$(printf '%s\n' "$@" --); [[ -f $LOG && $(<"$LOG")$'\n' == *"$want"* ]]; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "    rc: $rc
    out: $out
    err: $err
    cache: $(cat -A "$CACHE" 2>/dev/null)
    ssh: $(tr '\n' ' ' 2>/dev/null <"$LOG")"; fi; }

echo "ssh-sockets"

# --- the cache -------------------------------------------------------------

reset
config '{"statusline":{"sshHosts":{"forgejo":"git.example.org","github":"github.com"}}}'
run
check "writes both labels, in config order, with their control paths" \
    'silent && cached $'"'"'forgejo\t/x/cm-git.example.org\ngithub\t/x/cm-github.com\n'"'"
check "ssh gets -G, --, and the host, and nothing else" \
    'called -G -- git.example.org && called -G -- github.com && [[ $(grep -c -- "^-G$" "$LOG") == 2 ]]'
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
    'silent && cached $'"'"'ok\t/x/cm-github.com\n'"'"' && ! grep -q "^-o\|^-$" "$LOG"'

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
    'silent && cached $'"'"'ok\t/x/cm-github.com\n'"'"' && [[ $(grep -c -- "^-G$" "$LOG") == 1 ]]'

# --- no config, no file ----------------------------------------------------

for c in 'no key:{"statusline":{}}' 'an empty object:{"statusline":{"sshHosts":{}}}' \
    'a list:{"statusline":{"sshHosts":["github.com"]}}' 'an empty file:' 'not JSON:{"statusline":'; do
    reset
    config "${c#*:}"
    run
    check "no config, no file: ${c%%:*}" 'silent && nofile && [[ ! -e $LOG ]]'
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
config '{"statusline":{"sshHosts":{"stuck":"hang.example.org","github":"github.com"}}}'
run
check "an ssh that never returns is cut off, well inside the 10 s timeout" \
    'silent && ((took <= 5)) && cached $'"'"'github\t/x/cm-github.com\n'"'"
config '{"statusline":{"sshHosts":{"github":"github.com"}}}'

# --- as hooks.json runs it -------------------------------------------------

PLUGIN=${SELF%/*/*/*}
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
