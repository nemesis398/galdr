#!/usr/bin/env bash
# Tests for plan-track.sh, one directory up: the PostToolUse hook that
# records the last plan file a session edited, for the status line.
#
# Why these cases: the hook takes a session id and a file path from its
# input, and both are untrusted. The id names the state file, so a case
# feeds it `..` and slashes and checks that nothing lands outside
# galdr/plan/. The path decides whether a file is a plan, so cases feed it
# `..`, a symbolic link to a directory outside plans.dir, a subdirectory, a
# linked file and a trailing slash on plans.dir, and check that only a *.md
# directly in plans.dir, or a split plan's hub or part, is recorded, under
# its resolved path. A split plan's hub is <slug>/<slug>.md, its parts are
# <slug>/<slug> – *.md and one folder deeper, and every one of them records
# the hub, so cases check that a part, a deeper part and the hub record the
# hub, and that a linked part, a linked hub and a linked hub folder do not.
#
# The hook runs with a PATH of links to the tools it may use and nothing
# else, so a hook that starts calling an unlisted tool fails here first.
# HOME and XDG_STATE_HOME point into the sandbox, and the config comes from
# GALDR_CONFIG, so the user's own state and config are never read.
#
# Run:  bash plan-track.test.sh          (exit 0 = all green)
# PLAN_TRACK_UNDER_TEST=<file> tests another copy, for mutation runs.
# The sandbox lives under ${TMPDIR:-/tmp} and is removed on exit.

# The checks are eval'd, so their $ expand at check time, and the variables
# they read look unused to shellcheck.
# shellcheck disable=SC2016,SC2034

set -uo pipefail

# Paths are resolved with the cd -P builtin, not readlink -f, so the tests
# run on macOS too, where /tmp and /var/folders are links into /private.
case $0 in */*) here=${0%/*} ;; *) here=. ;; esac
HERE=$(cd -P -- "$here" && pwd -P) || { echo "cannot resolve $0" >&2; exit 2; }
HOOK=${PLAN_TRACK_UNDER_TEST:-${HERE%/*}/plan-track.sh}
HOOK=$(cd -P -- "${HOOK%/*}" 2>/dev/null && pwd -P)/${HOOK##*/}
[ -f "$HOOK" ] || { echo "missing $HOOK" >&2; exit 2; }
# shellcheck source=/dev/null
. "$HERE/lib/bsd-shims.sh"
bsd_each_userland "$HERE/${0##*/}" "$@"

SB=$(mktemp -d "${TMPDIR:-/tmp}/plan-track-test.XXXXXX")
SB=$(cd -P -- "$SB" && pwd -P)
trap 'rm -rf -- "$SB"' EXIT

pass=0 fail=0
ok()  { printf '  \e[32m✓\e[0m %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  \e[31m✗\e[0m %s\n%s\n' "$1" "$2"; fail=$((fail + 1)); }

# --- the sandbox -----------------------------------------------------------

SYS=$SB/sys NOJQ=$SB/nojq
mkdir -p "$SYS" "$NOJQ"
for t in bash find jq mkdir mv rm; do
    p=$(type -P "$t") || { echo "the tests need $t, which is not installed" >&2; exit 2; }
    ln -s "$p" "$SYS/$t"
    [[ $t == jq ]] || ln -s "$p" "$NOJQ/$t"
done
bsd_apply "$SYS" || exit 2
bsd_apply "$NOJQ" || exit 2

PLANS=$SB/vault/plans
mkdir -p "$PLANS/sub" "$SB/other" "$SB/home" "$SB/a b/plän"
printf -- '---\nprogress: 1\n---\n' >"$PLANS/2026-11-22-galdr.md"
printf -- '---\n---\n' >"$PLANS/sub/deep.md"
printf -- '---\n---\n' >"$PLANS/notes.txt"
printf -- '---\n---\n' >"$SB/other/x.md"
printf -- '---\n---\n' >"$SB/a b/plän/ü.md"
ln -s "$SB/other" "$PLANS/link"
ln -s "$SB/other/x.md" "$PLANS/linked.md"
ln -s "$PLANS" "$SB/plans-link"

# A split plan: the hub, a part, a part split one folder deeper, and what is
# no part of it. Its symbolic links lead outside or stand in for the hub.
HUBD=$PLANS/2026-11-26-mimir HUB=$PLANS/2026-11-26-mimir/2026-11-26-mimir.md
DEEP="$HUBD/2026-11-26-mimir – 5. Deep"
mkdir -p "$DEEP" "$SB/other/2026-11-27-away" "$PLANS/2026-11-28-lh" "$PLANS/2026-11-29-nohub"
printf -- '---\ntype: plan\nprogress: 40\n---\n' >"$HUB"
printf -- '---\ntype: plan-part\n---\n' >"$HUBD/2026-11-26-mimir – Task 18 galdr.md"
printf -- '---\ntype: plan-part\n---\n' >"$DEEP/2026-11-26-mimir – 5. Deep.md"
printf -- '---\ntype: plan-part\n---\n' >"$DEEP/2026-11-26-mimir – 5. Deep – 5.1 Leaf.md"
printf -- '---\n---\n' >"$HUBD/other.md"
printf -- '---\n---\n' >"$DEEP/other.md"
printf -- '---\n---\n' >"$PLANS/2026-11-29-nohub/2026-11-29-nohub – a.md"
printf -- '---\n---\n' >"$SB/other/2026-11-27-away/2026-11-27-away.md"
printf -- '---\n---\n' >"$SB/other/2026-11-27-away/2026-11-27-away – a.md"
printf -- '---\n---\n' >"$PLANS/2026-11-28-lh/2026-11-28-lh – a.md"
ln -s "$SB/other/x.md" "$HUBD/2026-11-26-mimir – linked.md"
ln -s "$SB/other/2026-11-27-away" "$PLANS/2026-11-27-away"
ln -s "$SB/other/x.md" "$PLANS/2026-11-28-lh/2026-11-28-lh.md"

STATE=$SB/state/galdr/plan
SID=c0ffee00-1234-4abc-8def-000000000001

# config <json>: the config file the next runs read.
config() { printf '%s\n' "$1" >"$SB/config.json"; }
config "{\"plans\":{\"dir\":\"$PLANS\"}}"

# run [ENV=VAL ...] -- JSON: the hook with the sandbox environment and JSON
# on stdin. Sets $out, $err and $rc.
run() {
    local envs=()
    while [[ $1 != -- ]]; do envs+=("$1"); shift; done
    shift
    out=$(printf '%s' "$1" | env -i HOME="$SB/home" PATH="$SYS" \
        XDG_STATE_HOME="$SB/state" GALDR_CONFIG="$SB/config.json" \
        "${envs[@]}" bash "$HOOK" 2>"$SB/err")
    rc=$?
    err=$(<"$SB/err")
}
# edit <session id> <file path>: a PostToolUse input for an Edit.
edit() {
    jq -nc --arg s "$1" --arg f "$2" \
        '{session_id: $s, hook_event_name: "PostToolUse", tool_name: "Edit", tool_input: {file_path: $f}}'
}
reset() { rm -rf "$SB/state"; }
recorded() { [[ -f $STATE/$SID && $(<"$STATE/$SID") == "$1" ]]; }
nothing() { [[ ! -e $SB/state ]] || [[ -z $(find "$SB/state" -type f) ]]; }
silent() { [[ $rc == 0 && -z $out && -z $err ]]; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "    rc: $rc
    out: $out
    err: $err
    state: $(find "$SB/state" 2>/dev/null)"; fi; }

echo "plan-track"

reset
run -- "$(edit "$SID" "$PLANS/2026-11-22-galdr.md")"
check "records a plan: the state file holds its absolute path" \
    'silent && recorded "$PLANS/2026-11-22-galdr.md"'
check "the state file is one line, and no temp file stays behind" \
    '(( $(find "$STATE" -type f | wc -l) == 1 && $(wc -l <"$STATE/$SID") == 1 ))'

run -- "$(edit "$SID" "$SB/other/x.md")"
check "a later edit outside plans.dir keeps the plan already recorded" \
    'silent && recorded "$PLANS/2026-11-22-galdr.md"'

reset
run -- "$(jq -nc --arg s "$SID" --arg f "$PLANS/2026-11-22-galdr.md" \
    '{session_id: $s, tool_name: "Write", tool_input: {file_path: $f, content: "x"}}')"
check "a Write records the plan as an Edit does" 'silent && recorded "$PLANS/2026-11-22-galdr.md"'

# --- not a plan ------------------------------------------------------------

for c in "outside plans.dir:$SB/other/x.md" \
    "a subdirectory:$PLANS/sub/deep.md" \
    "not a .md:$PLANS/notes.txt" \
    "a .. that leaves plans.dir:$PLANS/../../other/x.md" \
    "a symlinked parent that leads outside:$PLANS/link/x.md" \
    "a linked file that leads outside:$PLANS/linked.md" \
    "a file that does not exist:$PLANS/gone.md" \
    "a trailing slash on the file:$PLANS/2026-11-22-galdr.md/" \
    "a relative path:vault/plans/2026-11-22-galdr.md"; do
    reset
    run -- "$(edit "$SID" "${c#*:}")"
    check "ignores ${c%%:*}" 'silent && nothing'
done

# --- a split plan ----------------------------------------------------------

reset
run -- "$(edit "$SID" "$HUB")"
check "hub_in_subdir_recorded: the hub <slug>/<slug>.md records itself" 'silent && recorded "$HUB"'

for c in "a part:$HUBD/2026-11-26-mimir – Task 18 galdr.md" \
    "a part one folder deeper:$DEEP/2026-11-26-mimir – 5. Deep – 5.1 Leaf.md" \
    "the deeper folder's own hub:$DEEP/2026-11-26-mimir – 5. Deep.md" \
    "a part reached through ..:$DEEP/../2026-11-26-mimir – Task 18 galdr.md"; do
    reset
    run -- "$(edit "$SID" "${c#*:}")"
    check "part_records_hub: ${c%%:*} records the hub" 'silent && recorded "$HUB"'
done

reset
run -- "$(edit "$SID" "$HUB")"
run -- "$(edit "$SID" "$HUBD/other.md")"
check "a later edit of a note in the hub's folder that is no part keeps the hub" \
    'silent && recorded "$HUB"'

for c in "a linked part:$HUBD/2026-11-26-mimir – linked.md" \
    "a hub folder that links outside:$PLANS/2026-11-27-away/2026-11-27-away.md" \
    "a part in a hub folder that links outside:$PLANS/2026-11-27-away/2026-11-27-away – a.md" \
    "a part whose hub is a link:$PLANS/2026-11-28-lh/2026-11-28-lh – a.md" \
    "a hub that is a link:$PLANS/2026-11-28-lh/2026-11-28-lh.md"; do
    reset
    run -- "$(edit "$SID" "${c#*:}")"
    check "symlink_still_refused: ${c%%:*}" 'silent && nothing'
done

for c in "a note in the hub's folder that is no part:$HUBD/other.md" \
    "a note in the deeper folder that is no part:$DEEP/other.md" \
    "a part without its hub:$PLANS/2026-11-29-nohub/2026-11-29-nohub – a.md" \
    "a folder named like a hub, outside plans.dir:$SB/other/2026-11-27-away/2026-11-27-away.md"; do
    reset
    run -- "$(edit "$SID" "${c#*:}")"
    check "ignores ${c%%:*}" 'silent && nothing'
done

reset
run -- "$(edit "$SID" "$PLANS/sub/../2026-11-22-galdr.md")"
check "a .. that stays in plans.dir records the resolved path" \
    'silent && recorded "$PLANS/2026-11-22-galdr.md"'

reset
config "{\"plans\":{\"dir\":\"$SB/plans-link/\"}}"
run -- "$(edit "$SID" "$PLANS/2026-11-22-galdr.md")"
check "plans.dir as a symbolic link with a trailing slash still matches" \
    'silent && recorded "$PLANS/2026-11-22-galdr.md"'

reset
config "{\"plans\":{\"dir\":\"$SB/a b/plän\"}}"
run -- "$(edit "$SID" "$SB/a b/plän/ü.md")"
check "a plans.dir with a space and umlauts works" 'silent && recorded "$SB/a b/plän/ü.md"'

reset
config "{\"plans\":{\"dir\":\"$PLANS\"}}"
ESCP=$PLANS/$'esc\e[2Jname.md'
printf -- '---\n---\n' >"$ESCP"
run -- "$(edit "$SID" "$ESCP")"
check "ignores a real *.md in plans.dir whose name holds a control character (ESC)" 'silent && nothing'
rm -f -- "$ESCP"

# --- no plans.dir ----------------------------------------------------------

for c in 'no key:{"statusline":{}}' 'a relative dir:{"plans":{"dir":"vault/plans"}}' \
    'a dir that is no string:{"plans":{"dir":["x"]}}' 'an empty file:' 'not JSON:{"plans":'; do
    reset
    config "${c#*:}"
    run -- "$(edit "$SID" "$PLANS/2026-11-22-galdr.md")"
    check "ignores without plans.dir: ${c%%:*}" 'silent && nothing'
done
reset
run GALDR_CONFIG="$SB/no-such.json" -- "$(edit "$SID" "$PLANS/2026-11-22-galdr.md")"
check "ignores without plans.dir: a missing config file" 'silent && nothing'
config "{\"plans\":{\"dir\":\"$PLANS\"}}"

# --- the session id --------------------------------------------------------

reset
run -- "$(edit "../../../evil" "$PLANS/2026-11-22-galdr.md")"
check "rejects ../ in session id: nothing is written outside plan/" \
    'silent && [[ -z $(find "$SB" -newer "$SB/config.json" -type f ! -path "$STATE/*" ! -path "$SB/err") ]]'
check "the id is cleaned to [A-Za-z0-9-], as the status line cleans it" \
    '[[ $(cd "$STATE" && echo *) == evil ]]'

for s in '/' '../..' '' '. /'; do
    reset
    run -- "$(edit "$s" "$PLANS/2026-11-22-galdr.md")"
    check "an id with nothing left after cleaning ('$s') writes nothing" 'silent && nothing'
done
reset
run -- "$(jq -nc --arg f "$PLANS/2026-11-22-galdr.md" '{session_id: 42, tool_input: {file_path: $f}}')"
check "an id that is no string writes nothing" 'silent && nothing'

# --- failing open ----------------------------------------------------------

for c in 'garbage:not json' 'empty:' 'no tool_input:{"session_id":"abc"}' 'an array:[1,2]' \
    'a path with a newline:{"session_id":"abc","tool_input":{"file_path":"/x\n.md"}}'; do
    reset
    run -- "${c#*:}"
    check "exit 0 on ${c%%:*} stdin, nothing written" 'silent && nothing'
done

reset
run PATH="$NOJQ" -- "$(edit "$SID" "$PLANS/2026-11-22-galdr.md")"
check "exit 0 without jq, nothing written" 'silent && nothing'

reset
mkdir -p "$SB/state/galdr"
: >"$STATE"
run -- "$(edit "$SID" "$PLANS/2026-11-22-galdr.md")"
check "exit 0 when plan/ cannot be made (a file is in its place)" 'silent && [[ -f $STATE && ! -s $STATE ]]'

# --- pruning ---------------------------------------------------------------

reset
mkdir -p "$STATE"
printf '/x.md\n' >"$STATE/old-session"
printf '/x.md\n' >"$STATE/young-session"
touch -t 202001010000 "$STATE/old-session"
run -- "$(edit "$SID" "$PLANS/2026-11-22-galdr.md")"
check "a write prunes state files older than 30 days and keeps younger ones" \
    'silent && [[ ! -e $STATE/old-session && -e $STATE/young-session ]] && recorded "$PLANS/2026-11-22-galdr.md"'

# --- as hooks.json runs it -------------------------------------------------

PLUGIN=${HERE%/*/*}
mkdir -p "$SB/root space" && cp -r -- "$PLUGIN" "$SB/root space/galdr"
CMD=$(jq -r '.hooks.PostToolUse[] | select(.matcher == "Edit|Write") | .hooks[].command' "$PLUGIN/hooks/hooks.json")
reset
out=$(edit "$SID" "$PLANS/2026-11-22-galdr.md" | env -i HOME="$SB/home" PATH="$SYS" \
    XDG_STATE_HOME="$SB/state" GALDR_CONFIG="$SB/config.json" \
    CLAUDE_PLUGIN_ROOT="$SB/root space/galdr" bash -c "$CMD" 2>"$SB/err")
rc=$? err=$(<"$SB/err")
check "plugin-root-space: run as hooks.json writes it (Edit|Write), it records" \
    'silent && [[ $CMD == *plan-track.sh* ]] && recorded "$PLANS/2026-11-22-galdr.md"'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
