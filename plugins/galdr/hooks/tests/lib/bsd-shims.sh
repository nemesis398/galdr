# shellcheck shell=bash
# bsd-shims.sh: sourced by the hook tests, so a Linux machine can show how the
# hooks fare on macOS. Three userlands:
#   gnu    the tools as they are: GNU coreutils, timeout, setsid, flock
#   bsd    macOS without Homebrew's coreutils: stat and date take only their
#          BSD options, and timeout, setsid and flock do not exist
#   bsd-g  the same plus Homebrew's coreutils: gstat, gtimeout and gdate
# A test calls bsd_each_userland near its top, which runs the test once per
# userland with GALDR_USERLAND set, and then bsd_apply on each directory of
# tools it puts in a hook's PATH. On a machine whose stat and date are BSD's
# already, the shims pass every call through.

# _bsd_gnu <tool>: the path of a GNU (or uutils) <tool>, prefixed or not.
_bsd_gnu() {
    local c p
    for c in "g$1" "$1"; do
        p=$(type -P "$c") || continue
        "$p" --version 2>/dev/null | command grep -qE 'GNU|uutils' && { printf '%s\n' "$p"; return 0; }
    done
    return 1
}

# bsd_hides <tool>: true for the tools a BSD userland lacks.
bsd_hides() { [[ $1 == timeout || $1 == setsid || $1 == flock ]]; }

# bsd_can <userland>: true when this machine can play it.
bsd_can() {
    case $1 in
        gnu) [[ $(type -P stat) == "$(_bsd_gnu stat)" ]] && type -P timeout setsid flock >/dev/null ;;
        bsd) type -P stat date >/dev/null ;;
        bsd-g) _bsd_gnu stat >/dev/null && _bsd_gnu date >/dev/null && _bsd_gnu timeout >/dev/null ;;
        *) return 1 ;;
    esac
}

# bsd_each_userland <test script> [args...]: unless GALDR_USERLAND is set,
# runs the script once per userland this machine can play, then exits 0 when
# every run passed and 1 otherwise. With GALDR_USERLAND set it returns, and
# the test goes on in that userland.
bsd_each_userland() {
    [[ -n ${GALDR_USERLAND:-} ]] && return 0
    local u rc=0
    for u in gnu bsd bsd-g; do
        if ! bsd_can "$u"; then
            printf '\n=== userland %s: skipped, this machine lacks its tools\n' "$u"
            continue
        fi
        printf '\n=== userland %s\n' "$u"
        GALDR_USERLAND=$u "$BASH" "$@" || rc=1
    done
    exit "$rc"
}

# bsd_apply <dir>...: bsd_shims on each directory, as GALDR_USERLAND asks.
bsd_apply() {
    local d
    for d; do
        case ${GALDR_USERLAND:-gnu} in
            bsd) bsd_shims "$d" || return ;;
            bsd-g) bsd_shims "$d" --with-g || return ;;
        esac
    done
    return 0
}

# bsd_shims <dir> [--with-g]: fills <dir> with a stat that refuses -c and
# reads BSD's -f formats, and a date that refuses -d, -I and every long
# option and reads BSD's -r <seconds>, both failing as the BSD tools do; and
# hides timeout, setsid and flock by removing them from <dir>. With --with-g
# it adds gstat, gtimeout and gdate, links to the GNU tools. A PATH with <dir>
# first then looks like that Mac's to a hook.
bsd_shims() {
    local dir=$1 with_g=${2:-} stat_bin date_bin t p
    [[ -d $dir ]] || { echo "bsd_shims: $dir is no directory" >&2; return 2; }
    stat_bin=$(_bsd_gnu stat) || stat_bin=$(type -P stat) || { echo "bsd_shims: no stat" >&2; return 2; }
    date_bin=$(_bsd_gnu date) || date_bin=$(type -P date) || { echo "bsd_shims: no date" >&2; return 2; }
    rm -f -- "$dir/stat" "$dir/date" "$dir/timeout" "$dir/setsid" "$dir/flock" \
        "$dir/gstat" "$dir/gtimeout" "$dir/gdate"

    { printf '#!%s\n' "$BASH"
      if [[ $stat_bin == "$(_bsd_gnu stat)" ]]; then
          printf 'real=%q\n' "$stat_bin"
          cat <<'EOF'
# BSD stat on top of GNU stat: -f <format> with %m %a %c %u %g %z %N %Lp, -L.
usage() {
    printf 'stat: illegal option -- %s\n' "$1" >&2
    echo 'usage: stat [-FLnq] [-f format | -l | -r | -s | -x] [-t timefmt] [file ...]' >&2
    exit 1
}
fmt="" opts=()
while (($#)); do
    case $1 in
        --) shift; break ;;
        -L) opts+=(-L); shift ;;
        -f) (($# >= 2)) || usage f; fmt=$2; shift 2 ;;
        -f?*) fmt=${1#-f}; shift ;;
        -?*) usage "${1:1:1}" ;;
        *) break ;;
    esac
done
[[ -n $fmt ]] || { echo "stat: this shim needs -f <format>" >&2; exit 1; }
out=""
while [[ -n $fmt ]]; do
    case $fmt in
        %Lp*) out+=%a; fmt=${fmt:3} ;;
        %m*) out+=%Y; fmt=${fmt:2} ;;
        %a*) out+=%X; fmt=${fmt:2} ;;
        %c*) out+=%Z; fmt=${fmt:2} ;;
        %u*) out+=%u; fmt=${fmt:2} ;;
        %g*) out+=%g; fmt=${fmt:2} ;;
        %z*) out+=%s; fmt=${fmt:2} ;;
        %N*) out+=%n; fmt=${fmt:2} ;;
        %%*) out+=%%; fmt=${fmt:2} ;;
        %*) echo "stat: this shim does not know the format ${fmt:0:3}" >&2; exit 1 ;;
        *) out+=${fmt:0:1}; fmt=${fmt:1} ;;
    esac
done
exec "$real" "${opts[@]}" -c "$out" -- "$@"
EOF
      else
          printf 'exec %q "$@"\n' "$stat_bin"
      fi
    } >"$dir/stat"

    { printf '#!%s\n' "$BASH"
      if [[ $date_bin == "$(_bsd_gnu date)" ]]; then
          printf 'real=%q\n' "$date_bin"
          cat <<'EOF'
# BSD date on top of GNU date: -u, -r <seconds> and +<format>. GNU's -d, -I
# and long options fail as on macOS; the rest of BSD's date is not emulated.
opts=()
while (($#)); do
    case $1 in
        -u) opts+=(-u) ;;
        -r) (($# >= 2)) || { echo 'date: option requires an argument -- r' >&2; exit 1; }
            if [[ $2 =~ ^-?[0-9]+$ ]]; then opts+=(-d "@$2"); else opts+=(-r "$2"); fi
            shift ;;
        +*) opts+=("$1") ;;
        -d* | -I* | --*)
            printf 'date: illegal option -- %s\n' "${1:1:1}" >&2
            echo 'usage: date [-jnRu] [-r seconds|filename] [-v[+|-]val[ymwdHMS]] [[[mm]dd]HH]MM[[cc]yy][.ss] [+format]' >&2
            exit 1 ;;
        *) echo "date: this shim does not emulate $1" >&2; exit 1 ;;
    esac
    shift
done
exec "$real" "${opts[@]}"
EOF
      else
          printf 'exec %q "$@"\n' "$date_bin"
      fi
    } >"$dir/date"
    chmod +x "$dir/stat" "$dir/date"

    if [[ $with_g == --with-g ]]; then
        for t in stat timeout date; do
            p=$(_bsd_gnu "$t") || { echo "bsd_shims: no GNU $t for g$t" >&2; return 2; }
            ln -s -- "$p" "$dir/g$t"
        done
    fi
    return 0
}

# bash3_stub <dir>: puts a bash in <dir> that runs `bash <script> [args]` the
# way macOS's /bin/bash 3.2 would reach the script's version guard: the
# script runs with every BASH_VERSINFO read as 3.2.57. It tests the guard,
# not the rest of the script under bash 3.2.
bash3_stub() {
    { printf '#!%s\nreal=%q\n' "$BASH" "$BASH"
      cat <<'EOF'
script=${1:?usage: bash <script> [args]}
shift
src=$(<"$script") || exit 126
exec "$real" -c "_bash3_versinfo=(3 2 57 1 release x86_64-apple-darwin23)
${src//BASH_VERSINFO/_bash3_versinfo}" "$script" "$@"
EOF
    } >"$1/bash"
    chmod +x "$1/bash"
}
