#!/usr/bin/env bash
# Tests for statusline.sh, one directory up.
#
# Why fixtures instead of Claude Code: the status line's whole contract is the
# session JSON on stdin, a few environment variables, and one line on stdout.
# Driving the script directly lets each case give it exactly the input and
# the environment it needs.
#
# Every run goes through a parent bash, because Claude Code runs the script as
# a child of the claude process and the script reads the session kind from
# its parent's environment. Both environments are built from nothing
# (env -i), so the caller's own HOSTNAME, NO_COLOR, TZ or session kind never
# leak in. TZ is UTC unless a case sets another. The script's PATH holds a
# link to jq and nothing else: that is how a missing jq is simulated, and a
# script that starts calling another tool fails here first, with something on
# stderr.
#
# The quiet hosts come from the galdr config. Every run gets
# GALDR_CONFIG pointing at a file whose statusline.quietHosts is
# ["laptop"], so laptop stands for the machine where ordinary sessions run,
# and every other name for a machine that is not; a case passes its own
# GALDR_CONFIG= to change that.
#
# The cache age is measured against the clock, so every payload is stamped
# with an expiry relative to the moment it is built, 12 minutes and 30
# seconds into a one-hour cache. The half minute keeps a slow run from
# crossing a minute boundary. The reset times are fixed epochs, because the
# script only formats them.
#
# Run:  bash statusline.test.sh          (exit 0 = all green)
# The sandbox lives under ${TMPDIR:-/tmp} and is removed on exit.

set -uo pipefail

SELF=$(readlink -f "$0")
SL=${SELF%/*/*}/statusline.sh
[ -f "$SL" ] || { echo "missing $SL" >&2; exit 2; }
ENV_BIN=$(type -P env) || { echo "the tests need env, which is not installed" >&2; exit 2; }
JQ_BIN=$(type -P jq)   || { echo "the tests need jq, which is not installed" >&2; exit 2; }
DATE_BIN=$(type -P date) || { echo "the tests need date, which is not installed" >&2; exit 2; }

pass=0
fail=0
CASE=""
ERR="" RC=0

ok()  { pass=$((pass+1)); printf '  \033[32m✓\033[0m %s\n' "$CASE"; }
bad() { fail=$((fail+1)); printf '  \033[31m✗\033[0m %s\n     %s\n' "$CASE" "$1"
        printf 'stdout: %s\nstderr: %s\n' "$(cat -v "$ROOT/out")" "$ERR" | sed 's/^/       | /'; }

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statusline-test.XXXXXX")
trap 'rm -rf -- "$ROOT"' EXIT

WITH_JQ=$ROOT/with-jq NO_JQ=$ROOT/no-jq
mkdir -p "$WITH_JQ" "$NO_JQ"
ln -s "$JQ_BIN" "$WITH_JQ/jq"

# The config every run gets unless it passes its own.
QUIET='{"statusline":{"quietHosts":["laptop"]}}'
printf '%s\n' "$QUIET" >"$ROOT/values.json"

# values <text>: writes <text> to $ROOT/v.json, for a case's own values.
values() { printf '%s\n' "$1" >"$ROOT/v.json"; }

# The colors statusline.sh uses. Change them there and here together. The
# host tag is the accent fill: reverse video on the bright magenta slot,
# where the theme puts the accent, so the text takes the
# terminal's background.
TAG=$'\e[7;95m' YELLOW=$'\e[33m' RED=$'\e[1;31m' RESET=$'\e[0m'

# run_sl <stdin> [VAR=value...]: runs the script with PATH (the jq-only
# directory), TZ=UTC, GALDR_CONFIG (the quiet laptop above) and the
# given pairs as its whole environment, and sets ERR and RC. A later PATH=,
# TZ= or GALDR_CONFIG= overrides the default. PARENT_KIND, when
# set, goes into the parent's environment only, which is where Claude Code
# leaves CLAUDE_CODE_SESSION_KIND. TZDIR passes through when it is set, as
# in the Nix build sandbox, which has no /usr/share/zoneinfo.
run_sl() {
    local input=$1
    shift
    printf '%s' "$input" >"$ROOT/in"
    "$ENV_BIN" -i ${PARENT_KIND:+"CLAUDE_CODE_SESSION_KIND=$PARENT_KIND"} \
        "$BASH" -c '"$@"; exit $?' parent \
        "$ENV_BIN" -i PATH="$WITH_JQ" TZ=UTC ${TZDIR:+"TZDIR=$TZDIR"} \
        GALDR_CONFIG="$ROOT/values.json" "$@" "$BASH" "$SL" \
        <"$ROOT/in" >"$ROOT/out" 2>"$ROOT/err"
    RC=$?
    ERR=$(<"$ROOT/err")
}

# expect <line>: exit 0, nothing on stderr, and stdout exactly <line> plus a newline.
expect() {
    if   [ "$RC" -ne 0 ]; then bad "expected exit 0, got $RC"
    elif [ -n "$ERR" ];   then bad "expected nothing on stderr"
    elif ! cmp -s "$ROOT/out" <(printf '%s\n' "$1"); then bad "expected: $(printf '%s' "$1" | cat -v)"
    else ok; fi
}

# A payload as Claude Code 2.1.281 sent it to a status line on 2026-09-24,
# after the first response of a background session. Its prompt_cache expiry
# and the 1h ttl are restamped by fresh below.
FULL='{"session_id":"c0ffee00-1234-4abc-8def-000000000001","transcript_path":"/home/alice/.claude/projects/-home-alice-src-demo/c0ffee00-1234-4abc-8def-000000000001.jsonl","cwd":"/home/alice/src/demo","scratchpad_dir":"/tmp/claude-1000/-home-alice-src-demo/c0ffee00-1234-4abc-8def-000000000001/scratchpad","prompt_id":"0b5e55ed-0000-4000-8000-000000000002","session_name":"demo","model":{"id":"claude-haiku-4-5-20251001","display_name":"Haiku 4.5"},"workspace":{"current_dir":"/home/alice/src/demo","project_dir":"/home/alice/src/demo","added_dirs":[]},"version":"2.1.281","output_style":{"name":"default"},"cost":{"total_cost_usd":0.07882099999999999,"total_duration_ms":10252,"total_api_duration_ms":10013,"total_lines_added":0,"total_lines_removed":0},"context_window":{"total_input_tokens":37197,"total_output_tokens":699,"context_window_size":200000,"current_usage":{"input_tokens":10,"output_tokens":699,"cache_creation_input_tokens":37187,"cache_read_input_tokens":0},"used_percentage":19,"remaining_percentage":81},"exceeds_200k_tokens":false,"prompt_cache":{"warm":true,"caching_observed":true,"ttl":"1h","expires_at":1790257283,"requests":1,"misses":0,"expected_rebuilds":0,"hit_ratio":0,"cache_write_tokens":37187,"miss_recache_tokens":0,"last_miss_at":null,"last_miss_cause":null,"miss_causes":{},"recache_tokens_if_cold":37197},"fast_mode":false,"thinking":{"enabled":true},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":1790266800},"seven_day":{"used_percentage":6,"resets_at":1790542800}}}'

# fresh: FULL with the cache expiring in 2850 seconds, so its age is 750.
# The workspace is dropped, so line 1 is the whole output; placed adds it back.
fresh() { jq -c "del(.workspace, .cwd) | .prompt_cache.expires_at = $(( $("$DATE_BIN" +%s) + 2850 ))" <<<"$FULL"; }

# edit <jq filter>: fresh with the filter applied, compact.
edit() { fresh | jq -c "$1"; }

# The same instants as the script's local time, from date(1), which is
# independent of jq. A weekday is its first two letters in English.
FIVE_AT=1790266800 WEEK_AT=1790542800
hm()  { TZ=${2:-UTC} "$DATE_BIN" -d "@$1" +%H:%M; }
wd()  { local d; d=$(TZ=${2:-UTC} LC_ALL=C "$DATE_BIN" -d "@$1" +%a); printf '%s' "${d:0:2}"; }

# join <part>...: the parts as the script separates them.
join() { local out=$1; shift; local p; for p; do out+=" · $p"; done; printf '%s' "$out"; }

# The parts of a real payload.
P_MODEL="Haiku 4.5" P_CTX="ctx 19%" P_CACHE="cache 12m" P_SID=c0ffee00
P_5H="5h 30% ↻$(hm $FIVE_AT)" P_WK="wk 6% ↻$(wd $WEEK_AT)"
BODY=$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "$P_CACHE")

# The host tag the script prints for a host name: none on laptop, the quiet
# host of the default values, else the name on the accent fill.
host_tag() { [ "$1" = laptop ] || printf '%s' "${TAG}$1${RESET}"; }

# The kernel's name for this machine, as the script falls back to it.
read -r kernel_host </proc/sys/kernel/hostname
kernel_host=${kernel_host%%.*}

# --- the host -------------------------------------------------------------------

echo "the host"

CASE="a quiet host prints no host, only the parts of a real payload"
run_sl "$(fresh)" HOSTNAME=laptop
expect "$BODY"

CASE="a domain on a quiet host's name does not make it another host"
run_sl "$(fresh)" HOSTNAME=laptop.lan
expect "$BODY"

CASE="any other host prints as it is, on the accent fill, at the front"
run_sl "$(fresh)" HOSTNAME=build-box
expect "$BODY"$'\n'"$(host_tag build-box)"

CASE="the tag is the name itself: no prefix is dropped, and there is no table of known hosts"
run_sl "$(fresh)" HOSTNAME=old-laptop
expect "$BODY"$'\n'"${TAG}old-laptop${RESET}"

CASE="a domain on the name is dropped before the match"
run_sl "$(fresh)" HOSTNAME=other-host.lan
expect "$BODY"$'\n'"$(host_tag other-host)"

CASE="with no HOSTNAME in the environment, bash's own (the kernel's) name decides"
run_sl "" NO_COLOR=1 GALDR_CONFIG="$ROOT/no-values.json"
expect "$kernel_host"

CASE="an empty HOSTNAME falls back to the kernel's name"
run_sl "" HOSTNAME= NO_COLOR=1 GALDR_CONFIG="$ROOT/no-values.json"
expect "$kernel_host"

CASE="control characters in HOSTNAME are dropped, so the name cannot move the cursor"
run_sl "" HOSTNAME=$'build\e[2J-box\a' NO_COLOR=1
expect "build[2J-box"

CASE="a HOSTNAME of control characters alone counts as none"
run_sl "" HOSTNAME=$'\e\a' NO_COLOR=1 GALDR_CONFIG="$ROOT/no-values.json"
expect "$kernel_host"

CASE="the kernel's name is quiet when the values list it"
values "$(jq -cn --arg h "$kernel_host" '{statusline: {quietHosts: [$h]}}')"
run_sl "" HOSTNAME= NO_COLOR=1 GALDR_CONFIG="$ROOT/v.json"
expect ""

# --- the quiet hosts --------------------------------------------------------------

echo "the quiet hosts"

values '{"statusline":{"quietHosts":["laptop","server"]}}'
for h in laptop server; do
    CASE="every host statusline.quietHosts lists is quiet ($h of two)"
    run_sl "$(fresh)" HOSTNAME=$h GALDR_CONFIG="$ROOT/v.json"
    expect "$BODY"
done

CASE="a host the list leaves out still gets its tag"
run_sl "$(fresh)" HOSTNAME=build-box GALDR_CONFIG="$ROOT/v.json"
expect "$BODY"$'\n'"$(host_tag build-box)"

CASE="without a values file every host gets its tag, laptop too"
run_sl "$(fresh)" HOSTNAME=laptop GALDR_CONFIG="$ROOT/no-values.json"
expect "$BODY"$'\n'"${TAG}laptop${RESET}"

CASE="a values path that is a directory: every host gets its tag"
run_sl "$(fresh)" HOSTNAME=laptop GALDR_CONFIG="$ROOT"
expect "$BODY"$'\n'"${TAG}laptop${RESET}"

CASE="an empty list makes no host quiet"
values '{"statusline":{"quietHosts":[]}}'
run_sl "$(fresh)" HOSTNAME=laptop GALDR_CONFIG="$ROOT/v.json"
expect "$BODY"$'\n'"${TAG}laptop${RESET}"

for bad in '' 'not json' '{"statusline":' '[1,2]' '"laptop"' 'null' '{"statusline":"laptop"}' \
    '{"statusline":{"quietHosts":"laptop"}}' '{"statusline":{"quietHosts":{"laptop":true}}}' \
    '{"statusline":{"quietHosts":[["laptop"]]}}' '{"statusline":{"quietHosts":[{"name":"laptop"}]}}'; do
    CASE="values without a usable list ($bad): the tag prints, and the rest of the line too"
    values "$bad"
    run_sl "$(fresh)" HOSTNAME=laptop GALDR_CONFIG="$ROOT/v.json"
    expect "$BODY"$'\n'"${TAG}laptop${RESET}"
done

CASE="entries that are no string are skipped, and the strings still count"
values '{"statusline":{"quietHosts":[42,null,true,"laptop"]}}'
run_sl "$(fresh)" HOSTNAME=laptop GALDR_CONFIG="$ROOT/v.json"
expect "$BODY"

CASE="only the whole name matches, in its own case: no prefix, no longer name, no domain"
values '{"statusline":{"quietHosts":["hug","laptop2","LAPTOP","laptop.lan"," laptop"]}}'
run_sl "$(fresh)" HOSTNAME=laptop GALDR_CONFIG="$ROOT/v.json"
expect "$BODY"$'\n'"${TAG}laptop${RESET}"

CASE="other keys in the values change nothing"
values '{"web":{"searxngUrl":"http://127.0.0.1:1"},"statusline":{"quietHosts":["laptop"],"other":1}}'
run_sl "$(fresh)" HOSTNAME=laptop GALDR_CONFIG="$ROOT/v.json"
expect "$BODY"

CASE="the values are read from ~/.config/galdr/config.json without GALDR_CONFIG"
mkdir -p "$ROOT/home/.config/galdr"
printf '%s\n' "$QUIET" >"$ROOT/home/.config/galdr/config.json"
run_sl "$(fresh)" HOSTNAME=laptop GALDR_CONFIG= HOME="$ROOT/home"
expect "$BODY"

CASE="XDG_CONFIG_HOME moves the default values file"
run_sl "$(fresh)" HOSTNAME=laptop GALDR_CONFIG= HOME="$ROOT/home" XDG_CONFIG_HOME="$ROOT/elsewhere"
expect "$BODY"$'\n'"${TAG}laptop${RESET}"
mkdir -p "$ROOT/elsewhere/galdr"
cp "$ROOT/home/.config/galdr/config.json" "$ROOT/elsewhere/galdr/"
run_sl "$(fresh)" HOSTNAME=laptop GALDR_CONFIG= HOME="$ROOT/home" XDG_CONFIG_HOME="$ROOT/elsewhere"
expect "$BODY"

CASE="with neither HOME nor GALDR_CONFIG no file is read and the host gets its tag"
run_sl "$(fresh)" HOSTNAME=laptop GALDR_CONFIG=
expect "$BODY"$'\n'"${TAG}laptop${RESET}"

CASE="a values file that is a large JSON document is read all the same"
jq -cn '{padding: [range(20000) | "x\(.)"], statusline: {quietHosts: ["laptop"]}}' >"$ROOT/v.json"
run_sl "$(fresh)" HOSTNAME=laptop GALDR_CONFIG="$ROOT/v.json"
expect "$BODY"

# --- the session kind -------------------------------------------------------------

echo "the session kind"

CASE="bg in the parent's environment only, as in a real worker, prints bg first on a quiet host"
PARENT_KIND='bg' run_sl "$(fresh)" HOSTNAME=laptop
expect "$BODY"$'\n'"bg $P_SID"

CASE="bg comes after the host tag on another host"
PARENT_KIND='bg' run_sl "$(fresh)" HOSTNAME=other-host
expect "$BODY"$'\n'"$(host_tag other-host) · bg $P_SID"

CASE="bg in the script's own environment prints bg too"
run_sl "$(fresh)" HOSTNAME=laptop CLAUDE_CODE_SESSION_KIND=bg
expect "$BODY"$'\n'"bg $P_SID"

CASE="a parent kind other than bg prints nothing"
PARENT_KIND=daemon run_sl "$(fresh)" HOSTNAME=laptop
expect "$BODY"

# --- input that is not usable -------------------------------------------------------

echo "input that is not usable"

CASE="empty stdin on a quiet host prints an empty line"
run_sl "" HOSTNAME=laptop
expect ""

CASE="empty stdin elsewhere prints the host tag alone"
run_sl "" HOSTNAME=other-host
expect "$(host_tag other-host)"

CASE="malformed JSON prints the host tag alone"
run_sl '{"model": {"display_name": "Opus", ' HOSTNAME=other-host
expect "$(host_tag other-host)"

CASE="malformed JSON on a quiet host prints an empty line: the values are still read"
run_sl '{"model": {"display_name": "Opus", ' HOSTNAME=laptop
expect ""

CASE="stdin that is not UTF-8 prints the host tag alone"
run_sl $'\xff\xfe{"session_id":"x"}' HOSTNAME=other-host
expect "$(host_tag other-host)"

for input in '[1,2]' '"text"' '42' 'null'; do
    CASE="JSON that is not an object ($input) prints the host tag alone"
    run_sl "$input" HOSTNAME=other-host
    expect "$(host_tag other-host)"
done

CASE="of two JSON values only the first counts"
run_sl '{"model":{"display_name":"First"}} {"model":{"display_name":"Second"}}' HOSTNAME=laptop
expect "First"

CASE="with jq missing from PATH the host tag and bg still print, and nothing reaches stderr"
PARENT_KIND='bg' run_sl "$(fresh)" HOSTNAME=other-host PATH="$NO_JQ"
expect "$(host_tag other-host) · bg"

CASE="with jq missing a quiet host gets its tag too, because the values cannot be read"
PARENT_KIND='bg' run_sl "$(fresh)" HOSTNAME=laptop PATH="$NO_JQ"
expect "$(printf '%s' "${TAG}laptop${RESET}") · bg"

# --- the fields --------------------------------------------------------------------

echo "the fields"

CASE="a missing model drops the model alone"
run_sl "$(edit 'del(.model)')" HOSTNAME=laptop
expect "$(join "$P_CTX" "$P_5H" "$P_WK" "$P_CACHE")"

CASE="a null used_percentage (before the first response) drops the context alone"
run_sl "$(edit '.context_window.used_percentage = null | .context_window.current_usage = null')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_5H" "$P_WK" "$P_CACHE")"

CASE="a missing context_window drops the context alone"
run_sl "$(edit 'del(.context_window)')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_5H" "$P_WK" "$P_CACHE")"

CASE="a missing session_id leaves a bg tag without an id"
PARENT_KIND='bg' run_sl "$(edit 'del(.session_id)')" HOSTNAME=laptop
expect "$BODY"$'\n'"bg"

CASE="fields of the wrong type drop out instead of printing JSON or failing"
run_sl '{"model":"Opus","effort":"high","context_window":[1],"session_id":42,"rate_limits":[1],"prompt_cache":"warm"}' HOSTNAME=laptop
expect ""

CASE="a fractional percentage is rounded"
run_sl "$(edit '.context_window.used_percentage = 41.6')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "ctx 42%" "$P_5H" "$P_WK" "$P_CACHE")"

CASE="a percentage of 0 still prints"
run_sl "$(edit '.context_window.used_percentage = 0')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "ctx 0%" "$P_5H" "$P_WK" "$P_CACHE")"

CASE="the context percentage never changes color, whatever it reads"
run_sl "$(edit '.context_window.used_percentage = 95')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "ctx 95%" "$P_5H" "$P_WK" "$P_CACHE")"

CASE="control characters in a field are dropped, so the JSON cannot move the cursor"
# ESC, a newline and CSI (U+009B, written as its UTF-8 bytes), which jq escapes in the JSON.
name=$'Op\e[2J\nus\xc2\x9b'
run_sl "$(fresh | jq -c --arg n "$name" '.model.display_name = $n')" HOSTNAME=laptop
expect "$(join "Op[2Jus" "$P_CTX" "$P_5H" "$P_WK" "$P_CACHE")"

# --- the effort ----------------------------------------------------------------------

echo "the effort"

CASE="the effort level follows the model name"
run_sl "$(edit '.model.display_name = "Opus 5.5" | .effort = {"level":"high"}')" HOSTNAME=laptop
expect "$(join "Opus 5.5 high" "$P_CTX" "$P_5H" "$P_WK" "$P_CACHE")"

CASE="a missing effort (a model without the parameter) leaves the model alone"
run_sl "$(edit '.effort = null')" HOSTNAME=laptop
expect "$BODY"

CASE="an effort level that is no string drops out"
run_sl "$(edit '.effort = {"level":3}')" HOSTNAME=laptop
expect "$BODY"

CASE="an effort level without a model is not printed alone"
run_sl "$(edit 'del(.model) | .effort = {"level":"max"}')" HOSTNAME=laptop
expect "$(join "$P_CTX" "$P_5H" "$P_WK" "$P_CACHE")"

# --- the rate limits -------------------------------------------------------------------

echo "the rate limits"

CASE="the five-hour reset prints as local HH:MM and the weekly one as a two-letter weekday"
run_sl "$(edit '.rate_limits.five_hour.resets_at = 1790271900 | .rate_limits.seven_day.resets_at = 1790629200')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "5h 30% ↻$(hm 1790271900)" "wk 6% ↻$(wd 1790629200)" "$P_CACHE")"

CASE="the reset times follow the local time zone, here India's +05:30"
run_sl "$(fresh)" HOSTNAME=laptop TZ=Asia/Kolkata
expect "$(join "$P_MODEL" "$P_CTX" "5h 30% ↻$(hm $FIVE_AT Asia/Kolkata)" "wk 6% ↻$(wd $WEEK_AT Asia/Kolkata)" "$P_CACHE")"

CASE="the weekday names run Su to Sa, whatever the language of date(1)"
names=""
want=""
for k in 0 1 2 3 4 5 6; do
    at=$((WEEK_AT + k * 86400))
    run_sl "$(edit ".rate_limits.seven_day.resets_at = $at")" HOSTNAME=laptop
    names+=$(sed -n 's/.*wk 6% ↻\(..\) .*/\1 /p' "$ROOT/out")
    want+="$(wd $at) "
done
if [ "$names" = "$want" ] && [ "$(printf '%s' "$names" | tr ' ' '\n' | sort -u | wc -l)" -eq 7 ]; then ok
else bad "expected seven distinct days $want, got $names"; fi

CASE="a percentage turns yellow at 70, in the number alone"
run_sl "$(edit '.rate_limits.five_hour.used_percentage = 70')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "5h ${YELLOW}70%${RESET} ↻$(hm $FIVE_AT)" "$P_WK" "$P_CACHE")"

CASE="69.4 rounds to 69 and stays plain"
run_sl "$(edit '.rate_limits.five_hour.used_percentage = 69.4')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "5h 69% ↻$(hm $FIVE_AT)" "$P_WK" "$P_CACHE")"

CASE="69.5 rounds to 70 and turns yellow, so the color matches the number shown"
run_sl "$(edit '.rate_limits.five_hour.used_percentage = 69.5')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "5h ${YELLOW}70%${RESET} ↻$(hm $FIVE_AT)" "$P_WK" "$P_CACHE")"

CASE="89 is still yellow"
run_sl "$(edit '.rate_limits.seven_day.used_percentage = 89')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "wk ${YELLOW}89%${RESET} ↻$(wd $WEEK_AT)" "$P_CACHE")"

CASE="90 turns red"
run_sl "$(edit '.rate_limits.seven_day.used_percentage = 90')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "wk ${RED}90%${RESET} ↻$(wd $WEEK_AT)" "$P_CACHE")"

CASE="a limit past 100 is printed as it is, in red"
run_sl "$(edit '.rate_limits.five_hour.used_percentage = 104')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "5h ${RED}104%${RESET} ↻$(hm $FIVE_AT)" "$P_WK" "$P_CACHE")"

CASE="a window without resets_at keeps its percentage"
run_sl "$(edit 'del(.rate_limits.five_hour.resets_at)')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "5h 30%" "$P_WK" "$P_CACHE")"

CASE="a resets_at that is no number is left out, the percentage stays"
run_sl "$(edit '.rate_limits.five_hour.resets_at = "soon"')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "5h 30%" "$P_WK" "$P_CACHE")"

CASE="a window without a percentage drops out whole"
run_sl "$(edit 'del(.rate_limits.five_hour.used_percentage)')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_WK" "$P_CACHE")"

CASE="a percentage that is a string drops its window"
run_sl "$(edit '.rate_limits.seven_day.used_percentage = "6"')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_CACHE")"

CASE="a null window (Claude Code drops a lapsed one) drops out alone"
run_sl "$(edit '.rate_limits.five_hour = null')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_WK" "$P_CACHE")"

CASE="no rate_limits at all (an API key) drops both windows"
run_sl "$(edit 'del(.rate_limits)')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_CACHE")"

CASE="the gateway's spend_limit is not shown"
run_sl "$(edit '.rate_limits = {"spend_limit":{"used_percentage":62.8,"resets_at":1790266800,"used_usd":314.12,"limit_usd":500,"period":"monthly"}}')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_CACHE")"

# --- the per-model windows ---------------------------------------------------------------

echo "the per-model windows"

CASE="model_scoped entries print by display_name, right after the weekly limit"
run_sl "$(edit '.rate_limits.model_scoped = [{"display_name":"Fable","utilization":18,"resets_at":"2026-10-20T10:00:00Z"}]')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "Fable 18%" "$P_CACHE")"

CASE="seven_day_opus and seven_day_sonnet follow, as Opus and Sonnet"
run_sl "$(edit '.rate_limits.model_scoped = [{"display_name":"Fable","utilization":18.4,"resets_at":null}]
    | .rate_limits.seven_day_opus = {"utilization":55,"resets_at":"2026-10-20T10:00:00.000Z"}
    | .rate_limits.seven_day_sonnet = {"utilization":9,"resets_at":null}')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "Fable 18%" "Opus 55%" "Sonnet 9%" "$P_CACHE")"

CASE="a null seven_day_sonnet, as the usage reply has it, drops out alone"
run_sl "$(edit '.rate_limits.seven_day_opus = {"utilization":55,"resets_at":null} | .rate_limits.seven_day_sonnet = null')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "Opus 55%" "$P_CACHE")"

CASE="a model_scoped Opus is not printed twice when seven_day_opus is there too"
run_sl "$(edit '.rate_limits.model_scoped = [{"display_name":"Opus","utilization":40,"resets_at":null}]
    | .rate_limits.seven_day_opus = {"utilization":55,"resets_at":null}')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "Opus 40%" "$P_CACHE")"

CASE="entries without a name or without a number are skipped, the others stay"
run_sl "$(edit '.rate_limits.model_scoped = [{"display_name":"","utilization":5},{"display_name":"Gap","utilization":null},{"display_name":7,"utilization":6},{"utilization":8},"Fable",{"display_name":"Haiku","utilization":0}]')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "Haiku 0%" "$P_CACHE")"

CASE="an empty model_scoped prints nothing"
run_sl "$(edit '.rate_limits.model_scoped = []')" HOSTNAME=laptop
expect "$BODY"

CASE="a model_scoped that is no array prints nothing"
run_sl "$(edit '.rate_limits.model_scoped = {"display_name":"Fable","utilization":18}')" HOSTNAME=laptop
expect "$BODY"

CASE="a per-model percentage is colored like the other limits"
run_sl "$(edit '.rate_limits.model_scoped = [{"display_name":"Fable","utilization":72,"resets_at":null},{"display_name":"Other","utilization":95,"resets_at":null}]')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "Fable ${YELLOW}72%${RESET}" "Other ${RED}95%${RESET}" "$P_CACHE")"

CASE="control characters in a display_name are dropped"
name=$'Fa\e[2Jble\n'
run_sl "$(fresh | jq -c --arg n "$name" '.rate_limits.model_scoped = [{"display_name":$n,"utilization":18}]')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "Fa[2Jble 18%" "$P_CACHE")"

# --- the prompt cache ----------------------------------------------------------------------

echo "the prompt cache"

CASE="a warm cache prints its age in minutes, 12 for a 1h cache with 47m30s left"
run_sl "$(fresh)" HOSTNAME=laptop
expect "$BODY"

CASE="a cache written seconds ago reads 0m"
run_sl "$(edit '.prompt_cache.expires_at += 745')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "cache 0m")"

CASE="the 5m ttl counts its age from its own length"
run_sl "$(edit '.prompt_cache.ttl = "5m" | .prompt_cache.expires_at -= 2680')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "cache 2m")"

CASE="a cache the response reported as not warm is cold, with what the next turn rewrites"
run_sl "$(edit '.prompt_cache.warm = false | .prompt_cache.expires_at = null | .prompt_cache.recache_tokens_if_cold = 180123')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "cache cold (next turn rewrites ~180k)")"

CASE="a warm cache past its expiry is cold too, before Claude Code has resent the payload"
run_sl "$(edit '.prompt_cache.expires_at -= 3000')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "cache cold (next turn rewrites ~37k)")"

CASE="a cold cache with no size (right after a compaction) says only that it is cold"
run_sl "$(edit '.prompt_cache.warm = false | .prompt_cache.recache_tokens_if_cold = null')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "cache cold")"

CASE="a small rewrite is never rounded down to 0k"
run_sl "$(edit '.prompt_cache.warm = false | .prompt_cache.recache_tokens_if_cold = 300')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "cache cold (next turn rewrites ~1k)")"

CASE="caching_observed false (no caching, or a provider that does not report it) drops the part"
run_sl "$(edit '.prompt_cache.caching_observed = false | .prompt_cache.warm = false')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK")"

CASE="no prompt_cache yet (before the first response) drops the part"
run_sl "$(edit 'del(.prompt_cache)')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK")"

CASE="a prompt_cache that says nothing about warmth drops the part"
run_sl "$(edit 'del(.prompt_cache.warm)')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK")"

CASE="an expires_at that is no number on a warm cache drops the part"
run_sl "$(edit '.prompt_cache.expires_at = "soon"')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK")"

# --- the usage credits ----------------------------------------------------------------------

echo "the usage credits"

CASE="enabled extra usage prints used and limit in the currency's major unit"
run_sl "$(edit '.rate_limits.extra_usage = {"is_enabled":true,"monthly_limit":2000,"used_credits":420,"utilization":21,"currency":"EUR"}')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "$P_CACHE" "credits 4.20/20 €")"

CASE="extra usage that is not enabled prints nothing"
run_sl "$(edit '.rate_limits.extra_usage = {"is_enabled":false,"monthly_limit":2000,"used_credits":420,"currency":"EUR"}')" HOSTNAME=laptop
expect "$BODY"

CASE="a null extra_usage prints nothing"
run_sl "$(edit '.rate_limits.extra_usage = null')" HOSTNAME=laptop
expect "$BODY"

CASE="a limit that is not a whole amount keeps its cents, and 5 cents read 0.05"
run_sl "$(edit '.rate_limits.extra_usage = {"is_enabled":true,"monthly_limit":2050,"used_credits":5,"currency":"USD"}')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "$P_CACHE" "credits 0.05/20.50 \$")"

CASE="no monthly limit prints the spend alone, and a currency code without a symbol prints as it is"
run_sl "$(edit '.rate_limits.extra_usage = {"is_enabled":true,"monthly_limit":null,"used_credits":1234,"currency":"chf"}')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "$P_CACHE" "credits 12.34 CHF")"

CASE="no currency prints the amounts bare"
run_sl "$(edit '.rate_limits.extra_usage = {"is_enabled":true,"monthly_limit":2000,"used_credits":420}')" HOSTNAME=laptop
expect "$(join "$P_MODEL" "$P_CTX" "$P_5H" "$P_WK" "$P_CACHE" "credits 4.20/20")"

CASE="no used_credits drops the part"
run_sl "$(edit '.rate_limits.extra_usage = {"is_enabled":true,"monthly_limit":2000,"used_credits":null,"currency":"EUR"}')" HOSTNAME=laptop
expect "$BODY"

CASE="a used_credits that is a string drops the part"
run_sl "$(edit '.rate_limits.extra_usage = {"is_enabled":true,"monthly_limit":2000,"used_credits":"4.20","currency":"EUR"}')" HOSTNAME=laptop
expect "$BODY"

# --- line 2: place and work ---------------------------------------------------------

echo "line 2"

# placed <project> <current> [jq filter]: fresh with the workspace set.
placed() {
    fresh | jq -c --arg p "$1" --arg c "$2" \
        ".workspace = {project_dir: \$p, current_dir: \$c} | ${3:-.}"
}

H=$ROOT/home
mkdir -p "$H/proj/a b/ü" "$H/proj/.git" "$H/det/.git" "$H/plain" "$H/wt-main/.git/worktrees/x" "$H/wt"
printf 'ref: refs/heads/main\n' >"$H/proj/.git/HEAD"
printf '0123456789abcdef0123456789abcdef01234567\n' >"$H/det/.git/HEAD"
printf 'ref: refs/heads/feature/x\n' >"$H/wt-main/.git/worktrees/x/HEAD"
printf 'gitdir: %s\n' "$H/wt-main/.git/worktrees/x" >"$H/wt/.git"

CASE="two lines: the budget line without the session id, then the project and the branch"
run_sl "$(placed "$H/proj" "$H/proj")" HOSTNAME=laptop HOME="$H"
expect "$BODY"$'\n'"~/proj · main"

CASE="the current directory below the project prints relative to it, spaces and umlauts intact"
run_sl "$(placed "$H/proj" "$H/proj/a b/ü")" HOSTNAME=laptop HOME="$H"
expect "$BODY"$'\n'"~/proj ↳ a b/ü · main"

CASE="the current directory outside the project prints in full"
run_sl "$(placed "$H/proj" /var/tmp)" HOSTNAME=laptop HOME="$H"
expect "$BODY"$'\n'"~/proj ↳ /var/tmp · main"

CASE="a current directory under HOME prints with a ~ when outside the project"
run_sl "$(placed "$H/proj" "$H/plain")" HOSTNAME=laptop HOME="$H"
expect "$BODY"$'\n'"~/proj ↳ ~/plain · main"

CASE="a home that is a prefix of another path gives no ~"
run_sl "$(placed /home/user2/x /home/user2/x)" HOSTNAME=laptop HOME=/home/user
expect "$BODY"$'\n'"/home/user2/x"

CASE="the project equal to HOME prints as ~"
run_sl "$(placed "$H" "$H")" HOSTNAME=laptop HOME="$H"
expect "$BODY"$'\n'"~"

CASE="a detached HEAD prints its first 7 characters"
run_sl "$(placed "$H/det" "$H/det")" HOSTNAME=laptop HOME="$H"
expect "$BODY"$'\n'"~/det · 0123456"

CASE="a linked worktree (.git as a gitdir: file) prints its branch and wt"
run_sl "$(placed "$H/wt" "$H/wt")" HOSTNAME=laptop HOME="$H"
expect "$BODY"$'\n'"~/wt · feature/x wt"

CASE="no repository prints no branch"
run_sl "$(placed "$H/plain" "$H/plain")" HOSTNAME=laptop HOME="$H"
expect "$BODY"$'\n'"~/plain"

CASE="a .git file that is no gitdir: line prints no branch"
printf 'junk\n' >"$H/plain/.git"
run_sl "$(placed "$H/plain" "$H/plain")" HOSTNAME=laptop HOME="$H"
expect "$BODY"$'\n'"~/plain"
rm -f -- "$H/plain/.git"

CASE="bg puts the first 8 characters of the session id at the front of line 2"
PARENT_KIND='bg' run_sl "$(placed "$H/proj" "$H/proj")" HOSTNAME=laptop HOME="$H"
expect "$BODY"$'\n'"bg $P_SID · ~/proj · main"

CASE="without bg the session id is nowhere"
run_sl "$(placed "$H/proj" "$H/proj")" HOSTNAME=laptop HOME="$H"
if grep -q "$P_SID" "$ROOT/out"; then bad "the id was printed"; else ok; fi

CASE="the host tag and bg come before the project"
PARENT_KIND='bg' run_sl "$(placed "$H/proj" "$H/proj")" HOSTNAME=other-host HOME="$H"
expect "$BODY"$'\n'"$(host_tag other-host) · bg $P_SID · ~/proj · main"

CASE="a session id that is no plain id is cleaned to [A-Za-z0-9-]"
PARENT_KIND='bg' run_sl "$(placed "$H/proj" "$H/proj" '.session_id = "../x/y z"')" HOSTNAME=laptop HOME="$H"
expect "$BODY"$'\n'"bg xyz · ~/proj · main"

CASE="control characters in a path are dropped"
run_sl "$(placed $'/tmp/a\e[2Jb' $'/tmp/a\e[2Jb')" HOSTNAME=laptop HOME="$H"
expect "$BODY"$'\n'"/tmp/a[2Jb"

CASE="a workspace with no project prints no project part"
run_sl "$(placed "" "$H/proj")" HOSTNAME=laptop HOME="$H"
expect "$BODY"

CASE="garbage stdin and bg: the host tag and bg alone, on one line"
PARENT_KIND='bg' run_sl 'not json' HOSTNAME=other-host HOME="$H"
expect "$(host_tag other-host) · bg"

# --- the plan ----------------------------------------------------------------------

echo "the plan"

# plan-track.sh records the plan a session edits in
# $XDG_STATE_HOME/galdr/plan/<session id>, one line, its absolute path.
# track <path>: records <path> for the fixture's session.
PL=$ROOT/plans PSTATE=$ROOT/state/galdr/plan
P_SID_FULL=c0ffee00-1234-4abc-8def-000000000001
mkdir -p "$PL" "$PSTATE"
track() { printf '%s\n' "$1" >"$PSTATE/$P_SID_FULL"; }
printf -- '---\ntype: plan\nstatus: active\nprogress: 71\n---\n# x\nprogress: 5\n' >"$PL/2026-11-22-galdr.md"
printf -- '---\nstatus: done\nprogress: 100\n---\n' >"$PL/2026-11-20-done.md"
printf -- '---\nprogress: 30\n---\n' >"$PL/notes.md"
printf -- '# no frontmatter\nprogress: 50\n' >"$PL/2026-11-21-bare.md"
printf -- '---\nstatus: active\nprogress: lots\n---\n' >"$PL/2026-11-21-nan.md"
printf -- '---\r\nprogress: 42 \r\n---\r\n' >"$PL/2026-11-21-crlf.md"
{ printf -- '---\n'; for _ in $(seq 45); do printf 'k: v\n'; done; printf 'progress: 9\n---\n'; } >"$PL/2026-11-21-long.md"

CASE="plan 71%: the plan this session edits, with its progress"
track "$PL/2026-11-22-galdr.md"
run_sl "$(placed "$H/proj" "$H/proj")" HOSTNAME=laptop HOME="$H" XDG_STATE_HOME="$ROOT/state"
expect "$BODY"$'\n'"~/proj · main · plan galdr 71%"

CASE="plan done ✓: status done prints a check instead of the progress"
track "$PL/2026-11-20-done.md"
run_sl "$(placed "$H/proj" "$H/proj")" HOSTNAME=laptop HOME="$H" XDG_STATE_HOME="$ROOT/state"
expect "$BODY"$'\n'"~/proj · main · plan done ✓"

CASE="a name without a date prefix stays whole (notes.md gives notes)"
track "$PL/notes.md"
run_sl "$(placed "$H/proj" "$H/proj")" HOSTNAME=laptop HOME="$H" XDG_STATE_HOME="$ROOT/state"
expect "$BODY"$'\n'"~/proj · main · plan notes 30%"

CASE="plan file gone: no part"
track "$PL/2026-11-22-moved.md"
run_sl "$(placed "$H/proj" "$H/proj")" HOSTNAME=laptop HOME="$H" XDG_STATE_HOME="$ROOT/state"
expect "$BODY"$'\n'"~/proj · main"

CASE="no frontmatter: no part"
track "$PL/2026-11-21-bare.md"
run_sl "$(placed "$H/proj" "$H/proj")" HOSTNAME=laptop HOME="$H" XDG_STATE_HOME="$ROOT/state"
expect "$BODY"$'\n'"~/proj · main"

CASE="a frontmatter that does not close in 40 lines: no part"
track "$PL/2026-11-21-long.md"
run_sl "$(placed "$H/proj" "$H/proj")" HOSTNAME=laptop HOME="$H" XDG_STATE_HOME="$ROOT/state"
expect "$BODY"$'\n'"~/proj · main"

CASE="progress not a number: the name without a percentage"
track "$PL/2026-11-21-nan.md"
run_sl "$(placed "$H/proj" "$H/proj")" HOSTNAME=laptop HOME="$H" XDG_STATE_HOME="$ROOT/state"
expect "$BODY"$'\n'"~/proj · main · plan nan"

CASE="CRLF line ends and a trailing space are read"
track "$PL/2026-11-21-crlf.md"
run_sl "$(placed "$H/proj" "$H/proj")" HOSTNAME=laptop HOME="$H" XDG_STATE_HOME="$ROOT/state"
expect "$BODY"$'\n'"~/proj · main · plan crlf 42%"

CASE="a state file whose path is a directory: no part"
track "$PL"
run_sl "$(placed "$H/proj" "$H/proj")" HOSTNAME=laptop HOME="$H" XDG_STATE_HOME="$ROOT/state"
expect "$BODY"$'\n'"~/proj · main"

CASE="no state file for the session: no part"
rm -f -- "$PSTATE/$P_SID_FULL"
run_sl "$(placed "$H/proj" "$H/proj")" HOSTNAME=laptop HOME="$H" XDG_STATE_HOME="$ROOT/state"
expect "$BODY"$'\n'"~/proj · main"

CASE="a session id with ../ reads only the cleaned name under plan/"
printf '%s\n' "$PL/notes.md" >"$ROOT/state/galdr/evil"
printf '%s\n' "$PL/2026-11-22-galdr.md" >"$PSTATE/evil"
run_sl "$(placed "$H/proj" "$H/proj" '.session_id = "../evil"')" HOSTNAME=laptop HOME="$H" XDG_STATE_HOME="$ROOT/state"
expect "$BODY"$'\n'"~/proj · main · plan galdr 71%"

CASE="a session id with nothing left after cleaning: no part"
run_sl "$(placed "$H/proj" "$H/proj" '.session_id = "/.."')" HOSTNAME=laptop HOME="$H" XDG_STATE_HOME="$ROOT/state"
expect "$BODY"$'\n'"~/proj · main"
rm -f -- "$ROOT/state/galdr/evil" "$PSTATE/evil"

CASE="the plan prints without a project"
track "$PL/2026-11-22-galdr.md"
run_sl "$(placed "" "")" HOSTNAME=laptop HOME="$H" XDG_STATE_HOME="$ROOT/state"
expect "$BODY"$'\n'"plan galdr 71%"

CASE="control characters in the plan's name are dropped"
printf -- '---\nprogress: 1\n---\n' >"$PL/a"$'\e'"[2Jb.md"
track "$PL/a"$'\e'"[2Jb.md"
run_sl "$(placed "$H/proj" "$H/proj")" HOSTNAME=laptop HOME="$H" XDG_STATE_HOME="$ROOT/state"
expect "$BODY"$'\n'"~/proj · main · plan a[2Jb 1%"
rm -f -- "$PSTATE/$P_SID_FULL"

# --- the SSH masters -------------------------------------------------------------

echo "the SSH masters"

# ssh-sockets.sh (a SessionStart hook) caches each label's control socket
# path in $XDG_STATE_HOME/galdr/ssh-sockets, one <label>\t<path> line each.
# The script prints a label only when it is both in statusline.sshHosts and
# in the cache. sockets <line>...: writes those lines as the cache.
SSTATE=$ROOT/state/galdr
mkdir -p "$SSTATE"
sockets() { printf '%s\n' "$@" >"$SSTATE/ssh-sockets"; }
PYTHON_BIN=$(type -P python3) || { echo "the tests need python3, which is not installed" >&2; exit 2; }
# A real socket, kept short: a socket path has a length limit.
SOCK=$ROOT/s NOSOCK=$ROOT/nos
"$PYTHON_BIN" -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$SOCK"
: >"$ROOT/plain"
SSHV='{"statusline":{"quietHosts":["laptop"],"sshHosts":{"forgejo":"git.example.org","github":"github.com"}}}'
NOK="${YELLOW}✗${RESET}"
sl_ssh() { run_sl "$1" HOSTNAME=laptop HOME="$H" XDG_STATE_HOME="$ROOT/state" GALDR_CONFIG="$ROOT/v.json" "${@:2}"; }

CASE="socket up: a socket at the cached path gives ✓, a label not cached gives no entry"
values "$SSHV"
sockets "forgejo"$'\t'"$SOCK"
sl_ssh "$(placed "$H/proj" "$H/proj")"
expect "$BODY"$'\n'"~/proj · main · 🔑 forgejo ✓"

CASE="socket missing: nothing at the cached path gives ✗ in yellow"
sockets "forgejo"$'\t'"$SOCK" "github"$'\t'"$NOSOCK"
sl_ssh "$(placed "$H/proj" "$H/proj")"
expect "$BODY"$'\n'"~/proj · main · 🔑 forgejo ✓ github $NOK"

CASE="a plain file at the cached path is no socket: ✗"
sockets "forgejo"$'\t'"$ROOT/plain"
sl_ssh "$(placed "$H/proj" "$H/proj")"
expect "$BODY"$'\n'"~/proj · main · 🔑 forgejo $NOK"

CASE="a relative path in the cache is no socket: ✗"
sockets "forgejo"$'\t'"s"
sl_ssh "$(placed "$H/proj" "$H/proj")"
expect "$BODY"$'\n'"~/proj · main · 🔑 forgejo $NOK"

CASE="NO_COLOR gives a plain ✗"
sockets "forgejo"$'\t'"$SOCK" "github"$'\t'"$NOSOCK"
sl_ssh "$(placed "$H/proj" "$H/proj")" NO_COLOR=1
expect "$BODY"$'\n'"~/proj · main · 🔑 forgejo ✓ github ✗"

CASE="the order is the config's, not the cache's"
sockets "github"$'\t'"$NOSOCK" "forgejo"$'\t'"$SOCK"
sl_ssh "$(placed "$H/proj" "$H/proj")"
expect "$BODY"$'\n'"~/proj · main · 🔑 forgejo ✓ github $NOK"

CASE="label not in config: a cached label from an old config is not shown"
values '{"statusline":{"quietHosts":["laptop"],"sshHosts":{"forgejo":"git.example.org"}}}'
sockets "old"$'\t'"$SOCK" "forgejo"$'\t'"$SOCK" "garbage line"
sl_ssh "$(placed "$H/proj" "$H/proj")"
expect "$BODY"$'\n'"~/proj · main · 🔑 forgejo ✓"

CASE="only labels from another config are cached: no part"
sockets "old"$'\t'"$SOCK"
sl_ssh "$(placed "$H/proj" "$H/proj")"
expect "$BODY"$'\n'"~/proj · main"

CASE="no cache: no part"
values "$SSHV"
rm -f -- "$SSTATE/ssh-sockets"
sl_ssh "$(placed "$H/proj" "$H/proj")"
expect "$BODY"$'\n'"~/proj · main"

CASE="no sshHosts in the config: no part, whatever is cached"
values "$QUIET"
sockets "forgejo"$'\t'"$SOCK"
sl_ssh "$(placed "$H/proj" "$H/proj")"
expect "$BODY"$'\n'"~/proj · main"

CASE="a label with a control character, or whose host starts with -, is not shown"
values '{"statusline":{"quietHosts":["laptop"],"sshHosts":{"a\u001b[2Jb":"github.com","evil":"-oProxyCommand=x","ok":"github.com"}}}'
sockets "a"$'\e'"[2Jb"$'\t'"$SOCK" "evil"$'\t'"$SOCK" "ok"$'\t'"$SOCK"
sl_ssh "$(placed "$H/proj" "$H/proj")"
expect "$BODY"$'\n'"~/proj · main · 🔑 ok ✓"

CASE="the key follows the plan, and prints without a project"
values "$SSHV"
sockets "forgejo"$'\t'"$SOCK"
track "$PL/2026-11-22-galdr.md"
sl_ssh "$(placed "$H/proj" "$H/proj")"
expect "$BODY"$'\n'"~/proj · main · plan galdr 71% · 🔑 forgejo ✓"
rm -f -- "$PSTATE/$P_SID_FULL"
sl_ssh "$(placed "" "")"
expect "$BODY"$'\n'"🔑 forgejo ✓"

CASE="no jq: the host tag alone, no key"
sl_ssh "$(placed "$H/proj" "$H/proj")" PATH="$NO_JQ"
expect "${TAG}laptop${RESET}"
rm -f -- "$SSTATE/ssh-sockets"

# --- NO_COLOR --------------------------------------------------------------------

echo "NO_COLOR"

CASE="NO_COLOR=1 prints no escape sequence at all, host tag and limits included"
run_sl "$(edit '.rate_limits.five_hour.used_percentage = 95 | .rate_limits.seven_day.used_percentage = 75')" HOSTNAME=build-box NO_COLOR=1
expect "$(join "$P_MODEL" "$P_CTX" "5h 95% ↻$(hm $FIVE_AT)" "wk 75% ↻$(wd $WEEK_AT)" "$P_CACHE")"$'\n'"build-box"

CASE="an empty NO_COLOR leaves the colors on, as no-color.org defines it"
run_sl "$(edit '.rate_limits.five_hour.used_percentage = 95')" HOSTNAME=build-box NO_COLOR=
expect "$(join "$P_MODEL" "$P_CTX" "5h ${RED}95%${RESET} ↻$(hm $FIVE_AT)" "$P_WK" "$P_CACHE")"$'\n'"$(host_tag build-box)"

# --- the config file: missing, empty, malformed -----------------------------------

echo "the config file"

# A config the script cannot use is no config: exit 0, and the line it prints
# without the file, which gives laptop its tag.
: >"$ROOT/empty-config.json"
printf '{"statusline": {"quietHosts": ' >"$ROOT/malformed-config.json"
for c in "missing:$ROOT/no-such-config.json" "empty:$ROOT/empty-config.json" "malformed:$ROOT/malformed-config.json"; do
    CASE="config-${c%%:*}: the line is the one without a file"
    run_sl "$(fresh)" HOSTNAME=laptop GALDR_CONFIG="${c#*:}"
    expect "$BODY"$'\n'"${TAG}laptop${RESET}"
done
rm -f -- "$ROOT/empty-config.json" "$ROOT/malformed-config.json"

# --- plugin-root-space ------------------------------------------------------------

echo "plugin-root-space"

CASE="plugin-root-space: run from a copy of the plugin under a directory with a space"
PLUGIN=${SELF%/*/*/*}
mkdir -p -- "$ROOT/a b" && cp -r -- "$PLUGIN" "$ROOT/a b/galdr"
SL_SAVED=$SL SL="$ROOT/a b/galdr/statusline/statusline.sh"
run_sl "$(fresh)" HOSTNAME=laptop
expect "$BODY"
SL=$SL_SAVED

# --- summary ----------------------------------------------------------------------

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
