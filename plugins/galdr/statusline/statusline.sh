#!/usr/bin/env bash
# statusline.sh: the Claude Code status line (the plugin's README says how
# to wire it as the statusLine command). Prints two lines, every part
# only when its data exists, and a line with no part is not printed (the
# host tag always leads line 1, so line 1 always prints):
#   line 1: <host> · <model> <effort> · ctx <n>% · 5h <n>% ↻<HH:MM> · wk <n>% ↻<Mo> ·
#           <Model> <n>% ... · cache <n>m · credits <used>/<limit> €
#   line 2: [bg <id8> · ]<project> [↳ <dir>] · <branch> [wt] ·
#           plan <name> <n>%|✓ · 🔑 <label> ✓|✗ ... · ⚠ <hint> ·
#           ⚠ <n> sessions here · ⚠ /tmp <n>%
# The project is workspace.project_dir with $HOME as ~ (whole components
# only). ↳ shows the current directory relative to it when below it, in
# full when outside it. The branch comes from .git/HEAD, or from the gitdir:
# file of a linked worktree (then wt follows), read with `read`, no git.
# Fields reach bash tab-separated, each led by _ so that empty ones keep
# their place. The session id is cleaned to [A-Za-z0-9-] and printed
# (8 characters) only next to bg.
#
# The plan is the one plan-track.sh (a PostToolUse hook) last saw this
# session edit: it writes the plan's path to
# ${XDG_STATE_HOME:-~/.local/state}/galdr/plan/<session id>. The id is the
# cleaned one, so the read stays in that directory. Of the plan, at most the
# first 40 lines are read, up to the frontmatter's closing ---, for
# progress: and status:. status: done prints a check, a progress that is a
# whole number prints as a percentage, anything else prints the name alone.
# The name is the file's without .md and without a leading YYYY-MM-DD-. A
# plan that is gone, or has no frontmatter that closes, prints no part.
#
# The key shows whether each SSH master in statusline.sshHosts (label to
# host) still holds: ✓ when the control socket is there, ✗ in yellow when
# not. ssh-sockets.sh (a SessionStart hook) asks ssh for each socket's path
# and caches the lines <label>\t<path> in
# ${XDG_STATE_HOME:-~/.local/state}/galdr/ssh-sockets. A label prints only
# when it is both in the config and in the cache, in config order, so a
# cache left by an old config or another machine shows nothing that is no
# longer asked for. The labels come from jq, which drops an empty one, one
# with a control character, and one whose host is no string or starts with
# -, as the hook does. No cache yet, no part.
#
# Warnings. ⚠ <statusline.requiredEnvHint, else env> when a name in
# statusline.requiredEnv is missing from the claude process's environment (the
# parent's, read once with the session kind). ⚠ <n> sessions here counts the
# other processes whose /proc/<pid>/comm is claude and whose cwd is the
# project (GALDR_PROC replaces /proc for tests; the parent is skipped). Both
# read /proc, and without it (macOS) they turn off silently. ⚠ /tmp <n>% shows
# from 70% (red from 90%) for statusline.tmp.path (default /tmp), as a share
# of the filesystem or of statusline.tmp.shareBytes. The one process besides
# jq this script may start is `df -Pk <path>` (1024-blocks, used, available on
# Linux and macOS), at most every 300 s: its answer is cached in
# ${XDG_STATE_HOME:-~/.local/state}/galdr/tmp-usage as "<epoch> <used KiB>
# <size KiB>", written in place (mv would be a process). It needs that
# directory to exist, which the hooks make; without it df runs every time.
#
# Why: the line answers "can I keep going, and what does the next turn cost"
# without opening /usage. The limits and the cache age are what otherwise
# surprise a long session, the first as a refusal and the second as a bill.
#
# The host leads line 1 on every machine, before the model, because a
# session on another machine or over SSH looks the same as a local one
# otherwise. Where a session runs is place, and place gets the accent:
# reverse video on the bright magenta slot, which the theme gives the
# accent, so the name takes the terminal's background. The tag prints even
# when stdin is empty or garbage and jq is missing (line 1 is then the tag
# alone). The config key statusline.quietHosts, which used to silence the
# tag on chosen hosts, is retired: a config that still has it is ignored.
#
# The config is the JSON file that GALDR_CONFIG names, else
# ${XDG_CONFIG_HOME:-~/.config}/galdr/config.json. A file that is missing,
# empty or not JSON makes the keys below take their defaults.
#
# The host is $HOSTNAME without a domain. Bash keeps an inherited HOSTNAME
# (some distributions' /etc/profile export one, and the tests set one), and
# an empty one falls back to the kernel's name. Either way it names the
# machine this script runs on, which is where the session runs.
#
# `bg` marks a background worker. Claude Code removes CLAUDE_CODE_SESSION_KIND
# from the environment of every command it runs, this one included, so the
# script reads it from its parent's environment, which is the claude process.
#
# The rest comes from the session JSON on stdin, in the same jq call that
# reads the config:
#   - model.display_name, then effort.level, which is absent on a model
#     without the effort parameter;
#   - context_window.used_percentage, null before the first response. Like
#     the percentage /context prints, it is of autoCompactWindow, not of the
#     model's 1M window: 32k in use at a 500k window reads 6%, not 3%;
#   - rate_limits.five_hour and .seven_day, each {used_percentage, resets_at}
#     with resets_at in epoch seconds, sent to claude.ai subscribers after the
#     first response. A percentage turns yellow at 70 and red at 90, judged on
#     the rounded number that is printed;
#   - prompt_cache, from the first response on: warm, ttl ("5m" or "1h") and
#     expires_at. expires_at minus the ttl is when the cache was last written
#     or read, so its age is now minus that. A cache past expires_at, or not
#     warm, is cold, and recache_tokens_if_cold (null right after a
#     compaction) is what the next turn rewrites. The age moves only when the
#     script runs again, which is after a message, at expires_at, and every
#     refreshInterval seconds if the statusLine setting has one;
#   - workspace.project_dir, workspace.current_dir and session_id for line 2,
#     followed by the labels of statusline.sshHosts and the names of
#     statusline.requiredEnv (each list one field), the requiredEnvHint, and
#     statusline.tmp.path and .shareBytes.
# Per-model weekly windows (rate_limits.model_scoped[] by display_name, then
# seven_day_opus and seven_day_sonnet, each {utilization, resets_at}) and
# extra_usage (amounts in minor units of its currency) are the shapes of the
# usage reply behind /usage. Claude Code 2.1.302 does not put them into the
# status line payload, so those parts print only once it does.
# Control characters are dropped, so nothing in the JSON can move the cursor.
#
# Claude Code reruns this after every assistant message, shows it only on
# exit 0, and cancels a run the next refresh overtakes. So it starts no
# process but that one jq and the df above (at most every 300 s while the
# galdr state directory exists, else on every run), and always exits 0.
# NO_COLOR (set and not empty) turns the colors off. No set -e or -u: the host must print whatever fails.

# Control characters are dropped from the name, as from the JSON below.
host=${HOSTNAME//[[:cntrl:]]/}
host=${host%%.*}
if [[ -z $host ]]; then
    read -r host 2>/dev/null </proc/sys/kernel/hostname
    host=${host//[[:cntrl:]]/}
    host=${host%%.*}
fi
host=${host:-?}

color_on=1
[[ -n ${NO_COLOR:-} ]] && color_on=""

values=${GALDR_CONFIG:-${XDG_CONFIG_HOME:-${HOME:-/nonexistent}/.config}/galdr/config.json}
[[ -f $values && -r $values ]] || values=/dev/null

# The parent's environment is read once, for the session kind and for the
# names requiredEnv asks about, from ${GALDR_PROC:-/proc}/$PPID/environ.
# Without /proc (macOS) env_ok stays empty, the requiredEnv check is off and
# the kind comes from the script's own environment only.
kind=${CLAUDE_CODE_SESSION_KIND:-}
env_ok="" parent_names=" "
if mapfile -d '' -t parent_env 2>/dev/null <"${GALDR_PROC:-/proc}/$PPID/environ"; then
    env_ok=1
    for kv in "${parent_env[@]}"; do
        [[ $kv == *=?* ]] && parent_names+="${kv%%=*} "
        if [[ -z $kind && $kv == CLAUDE_CODE_SESSION_KIND=* ]]; then kind=${kv#*=}; fi
    done
fi
# One output line: the fields joined by tabs. Only the first JSON value on stdin is read, and
# input that does not parse counts as none. Every path step carries a ?, so a
# field of the wrong type, or input that is no object at all, drops a part
# instead of failing. The jq variables ($c, $n, ...) must reach jq
# unexpanded.
# shellcheck disable=SC2016
prog='
def text(f): ((f)? | select(type == "string")) // "" | gsub("[[:cntrl:]]"; "");
def used: (.used_percentage? // .utilization?) | numbers;
def lim:
    round as $n
    | (if $n >= 90 then "\u001b[1;31m" elif $n >= 70 then "\u001b[33m" else "" end) as $k
    | if $k != "" and $c != "" then "\($k)\($n)%\u001b[0m" else "\($n)%" end;
def hm: strflocaltime("%H:%M");
def wd: localtime | ["Su","Mo","Tu","We","Th","Fr","Sa"][.[6]];
def win(name; fmt):
    objects as $o
    | ($o | used) as $p
    | (($o | .resets_at? | numbers | fmt)? // "") as $r
    | "\(name) \($p | lim)" + (if $r != "" then " ↻\($r)" else "" end);
def cents: [round, 0] | max | . as $m | "\($m / 100 | floor).\(("0" + "\($m % 100)")[-2:])";
def cold($p):
    "cache cold" + ((($p | .recache_tokens_if_cold | numbers | select(. > 0)) // null)
        | if . then " (next turn rewrites ~\([(. / 1000 | round), 1] | max)k)" else "" end);
def cache:
    (.prompt_cache? | objects | select(.caching_observed != false)) as $p
    | $p.warm as $warm
    | (if ($p.expires_at | type) == "number" then $p.expires_at else null end) as $exp
    | ({"5m": 300, "1h": 3600}[($p.ttl | strings) // ""] // 3600) as $ttl
    | now as $now
    | if $warm == true and $exp != null and $exp > $now then
          "cache \([$now - ($exp - $ttl), 0] | max | . / 60 | floor)m"
      elif $warm == false or ($warm == true and $exp != null) then cold($p)
      else empty end;
def credits:
    (.rate_limits? | objects | .extra_usage? | objects | select(.is_enabled == true)) as $x
    | ($x | .used_credits? | numbers) as $u
    | (($x | .monthly_limit? | numbers) // null) as $l
    | (text($x | .currency) | .[0:8] | ascii_upcase) as $cur
    | "credits " + ($u | cents)
      + (if $l then "/" + ($l | round | if . % 100 == 0 then "\(. / 100)" else cents end) else "" end)
      + ({"EUR": " €", "USD": " $", "GBP": " £"}[$cur] // (if $cur != "" then " " + $cur else "" end));
def scoped:
    ((.rate_limits? | objects | .model_scoped? | arrays | .[] | objects) as $m
        | {n: text($m | .display_name), o: $m}),
    (.rate_limits? | objects
        | (.seven_day_opus? | objects | {n: "Opus", o: .}),
          (.seven_day_sonnet? | objects | {n: "Sonnet", o: .}))
    | select(.n != "" and (.o | used) != null);
def ssh_labels:
    ($values | try fromjson catch null)
    | objects | .statusline? | objects | .sshHosts? | objects | to_entries[]
    | select((.key | test("^[^[:cntrl:]]+$"))
        and (.value | type) == "string" and (.value | test("^[^-[:cntrl:]][^[:cntrl:]]*$")))
    | .key;
def cfgv(f):
    [($values | try fromjson catch null) | objects | .statusline? | objects | f] | .[0] // "";
def cfgt(f): cfgv(f) | gsub("[[:cntrl:]]"; "");
def required_env:
    ($values | try fromjson catch null)
    | objects | .statusline? | objects | .requiredEnv? | arrays | .[] | strings
    | select(test("^[A-Za-z_][A-Za-z0-9_]*$"));
def body:
[ (text(.model?.display_name) as $m | text(.effort?.level) as $e
       | if $m != "" and $e != "" then "\($m) \($e)" else $m end),
  (((.context_window?.used_percentage)? | numbers | round | "ctx \(.)%")),
  (.rate_limits? | objects | .five_hour? | win("5h"; hm)),
  (.rate_limits? | objects | .seven_day? | win("wk"; wd)),
  ([scoped] | reduce .[] as $e ([]; if any(.[]; .n == $e.n) then . else . + [$e] end)
      | .[] | "\(.n) \(.o | used | lim)"),
  cache,
  credits
] | map(select(. != "")) | join(" · ");

(try input catch null) as $in
| [($in | body),
   ($in | text(.workspace?.project_dir)),
   ($in | text(.workspace?.current_dir)),
   ($in | text(.session_id) | gsub("[^A-Za-z0-9-]"; "")),
   ([ssh_labels] | join("\u001f")),
   ([required_env] | join("\u001f")),
   cfgt(.requiredEnvHint? | strings),
   cfgt(.tmp? | objects | .path? | strings),
   cfgv(.tmp? | objects | .shareBytes? | numbers | select(. > 0) | floor | tostring)]
| map("_" + .) | join("\t")'
# Every field leads with _, which is stripped below: read splits on a tab as
# on white space, so an empty field would otherwise swallow its neighbour.
fields=()
IFS=$'\t' read -r -a fields <<<"$(jq -nr --arg c "$color_on" \
    --rawfile values "$values" "$prog" 2>/dev/null)"
for i in "${!fields[@]}"; do fields[i]=${fields[i]#_}; done
line1=${fields[0]} project_dir=${fields[1]}
current_dir=${fields[2]} session_id=${fields[3]}
# The labels come as one field, joined by \x1f, which no label can hold, so
# the fields keep their places and later ones follow this one.
ssh_labels=()
[[ -n ${fields[4]-} ]] && IFS=$'\x1f' read -r -a ssh_labels <<<"${fields[4]}"
required_env=()
[[ -n ${fields[5]-} ]] && IFS=$'\x1f' read -r -a required_env <<<"${fields[5]}"
env_hint=${fields[6]-} tmp_path=${fields[7]:-/tmp} tmp_share=${fields[8]-}

# short_path <abs>: sets short to the path with $HOME as ~, on a whole
# component only, so /home/user2 is not ~2 under HOME=/home/user. It sets a
# global instead of printing, so no subshell is forked.
short_path() {
    local p=$1 h=${HOME%/}
    if [[ -n $h && $p == "$h" ]]; then short='~'
    elif [[ -n $h && $p == "$h"/* ]]; then short="~"/${p#"$h"/}
    else short=$p; fi
}

# git_branch <dir>: sets branch (name, short sha or empty) and wt (1 in a
# linked worktree), from <dir>/.git/HEAD or the gitdir: file a worktree or a
# submodule has. Only a linked worktree's gitdir holds a commondir file, so
# a submodule gets no wt. A gitdir or HEAD that is gone gives no branch and
# nothing on stderr. It sets globals instead of printing, so no subshell is
# forked.
git_branch() {
    local d=$1 g=$1/.git head="" line=""
    branch="" wt=""
    if [[ -d $g ]]; then
        head=$g/HEAD
    elif [[ -f $g ]]; then
        { read -r line || [[ -n $line ]]; } 2>/dev/null <"$g"
        [[ $line == "gitdir: "* ]] || return 0
        line=${line#gitdir: }
        [[ $line == /* ]] || line=$d/$line
        head=$line/HEAD
        [[ -f $line/commondir ]] && wt=1
    else
        return 0
    fi
    line=""
    { read -r line || [[ -n $line ]]; } 2>/dev/null <"$head"
    line=${line//[[:cntrl:]]/}
    if [[ $line == "ref: refs/heads/"* ]]; then branch=${line#ref: refs/heads/}
    elif [[ $line == "ref: "* ]]; then branch=${line#ref: }
    else branch=${line:0:7}; fi
    [[ -n $branch ]] || wt=""
}

# plan_of <state file>: sets plan to "plan <name> <n>%", "plan <name> ✓",
# "plan <name>" or nothing, from the plan whose path the state file holds.
# It sets a global instead of printing, so no subshell is forked.
plan_of() {
    local f="" line="" n=0 closed="" progress="" status="" name
    plan=""
    { read -r f || [[ -n $f ]]; } 2>/dev/null <"$1" || return 0
    [[ $f == /*.md && -f $f && -r $f ]] || return 0
    while ((n++ < 40)) && line="" && { IFS= read -r line || [[ -n $line ]]; }; do
        line=${line%$'\r'}
        if ((n == 1)); then [[ $line == --- ]] || return 0; continue; fi
        if [[ $line == --- ]]; then closed=1; break; fi
        case $line in
            progress:*) progress=${line#progress:} ;;
            status:*) status=${line#status:} ;;
        esac
    done 2>/dev/null <"$f"
    [[ -n $closed ]] || return 0
    progress=${progress//[\"\'[:space:]]/} status=${status//[\"\'[:space:]]/}
    name=${f##*/}
    name=${name%.md}
    [[ $name =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-(.+)$ ]] && name=${BASH_REMATCH[1]}
    name=${name//[[:cntrl:]]/}
    [[ -n $name ]] || return 0
    plan="plan $name"
    if [[ $status == "done" ]]; then plan+=" ✓"
    elif [[ $progress =~ ^[0-9]+$ ]]; then plan+=" $progress%"; fi
}

# Line 2, one part at a time, joined with " · ". Later parts append to parts.
parts=()
if [[ $kind == bg ]]; then
    parts+=("bg${session_id:+ ${session_id:0:8}}")
fi
if [[ -n $project_dir ]]; then
    proj=$project_dir cur=$current_dir
    [[ $proj == / ]] || proj=${proj%/}
    [[ $cur == / ]] || cur=${cur%/}
    short_path "$proj"
    part=$short
    if [[ -z $cur || $cur == "$proj" ]]; then :
    elif [[ $cur == "$proj"/* ]]; then part+=" ↳ ${cur#"$proj"/}"
    else { short_path "$cur"; part+=" ↳ $short"; }; fi
    parts+=("$part")
    git_branch "$proj"
    [[ -n $branch ]] && parts+=("$branch${wt:+ wt}")
fi
if [[ -n $session_id ]]; then
    plan_of "${XDG_STATE_HOME:-${HOME:-/nonexistent}/.local/state}/galdr/plan/$session_id"
    [[ -n $plan ]] && parts+=("$plan")
fi
if ((${#ssh_labels[@]})); then
    keys="" c_labels=() c_paths=()
    while IFS=$'\t' read -r l p || [[ -n $l ]]; do
        c_labels+=("$l") c_paths+=("$p")
    done 2>/dev/null <"${XDG_STATE_HOME:-${HOME:-/nonexistent}/.local/state}/galdr/ssh-sockets"
    for l in "${ssh_labels[@]}"; do
        for i in "${!c_labels[@]}"; do
            [[ ${c_labels[i]} == "$l" ]] || continue
            p=${c_paths[i]}
            if [[ $p == /* && -S $p ]]; then keys+=" $l ✓"
            elif [[ -n $color_on ]]; then keys+=" $l "$'\e[33m✗\e[0m'
            else keys+=" $l ✗"; fi
            break
        done
    done
    [[ -n $keys ]] && parts+=("🔑$keys")
fi

# Warnings. A name of requiredEnv missing from the claude process's
# environment, other claude processes with this project as their cwd (the
# parent is skipped), and a full /tmp. The first two read /proc and are off
# without it.
if [[ -n $env_ok ]]; then
    for n in "${required_env[@]}"; do
        if [[ $parent_names != *" $n "* ]]; then parts+=("⚠ ${env_hint:-env}"); break; fi
    done
fi
if [[ -n $project_dir ]]; then
    n=0 proc=${GALDR_PROC:-/proc}
    for d in "$proc"/[0-9]*; do
        [[ ${d##*/} == "$PPID" ]] && continue
        c=""
        read -r c 2>/dev/null <"$d/comm" || continue
        if [[ $c == claude && $d/cwd -ef $proj ]]; then n=$((n + 1)); fi
    done
    plural=s
    ((n == 1)) && plural=""
    ((n)) && parts+=("⚠ $n session$plural here")
fi
# /tmp: df is the one process this script may start besides jq, at most
# every 300 s. Its answer is cached as "<epoch> <used KiB> <size KiB>".
tmp_file=${XDG_STATE_HOME:-${HOME:-/nonexistent}/.local/state}/galdr/tmp-usage
printf -v now '%(%s)T' -1
t_at="" t_used="" t_size=""
read -r t_at t_used t_size 2>/dev/null <"$tmp_file"
if ! [[ $t_at =~ ^[0-9]+$ && $t_used =~ ^[0-9]+$ && $t_size =~ ^[0-9]+$ ]] \
    || ((t_at > now || now - t_at >= 300)); then
    t_used="" t_size=""
    df_out=$(df -Pk -- "$tmp_path" 2>/dev/null)
    { read -r _; read -r _ t_size t_used _; } <<<"$df_out"
    if [[ $t_used =~ ^[0-9]+$ && $t_size =~ ^[0-9]+$ ]]; then
        { printf '%s %s %s\n' "$now" "$t_used" "$t_size" >"$tmp_file"; } 2>/dev/null
    else
        t_used=""
    fi
fi
if [[ -n $t_used ]]; then
    if [[ $tmp_share =~ ^[0-9]+$ ]] && ((tmp_share > 0)); then
        pct=$(((t_used * 1024 * 100 + tmp_share / 2) / tmp_share))
    elif ((t_size > 0)); then
        pct=$(((t_used * 100 + t_size / 2) / t_size))
    else
        pct=0
    fi
    if ((pct >= 70)); then
        part="⚠ ${tmp_path} $pct%"
        if [[ -z $color_on ]]; then :
        elif ((pct >= 90)); then part=$'\e[1;31m'$part$'\e[0m'
        else part=$'\e[33m'$part$'\e[0m'; fi
        parts+=("$part")
    fi
fi

line2=""
for part in "${parts[@]}"; do line2+=${line2:+ · }$part; done

# The host tag leads line 1, which therefore always prints.
tag=$host
[[ -n $color_on ]] && tag=$'\e[7;95m'$host$'\e[0m'
printf '%s\n' "$tag${line1:+ · $line1}"
if [[ -n $line2 ]]; then printf '%s\n' "$line2"; fi
exit 0
