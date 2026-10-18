#!/usr/bin/env bash
set -euo pipefail

# Orchestration entry for just repo update / pkg-update. One node's failure does not stop later nodes;
# network-kind nodes retry once automatically. At the end, failed nodes are summarized and the full log
# directory is kept, or removed when everything succeeded. On a TTY the status line refreshes in place
# while running (tail of the current activity, or spinner+elapsed when silent); without a TTY it degrades
# to static output.

usage() { echo "usage: $0 pkg | all [flake-input...]" >&2; }

if [[ ${1:-} != "pkg" && ${1:-} != "all" ]]; then
  usage
  exit 2
fi
mode=$1
shift
if [[ $mode == "pkg" && $# -gt 0 ]]; then
  usage
  exit 2
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd -- "$repo_root"

logs_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotnix-update.XXXXXX")"
keep_logs=0
failures=()
child_pid=
is_tty=0
[[ -t 1 ]] && is_tty=1
spin_frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

cleanup() { ((keep_logs)) || rm -rf -- "$logs_dir"; }
trap cleanup EXIT
on_int() {
  keep_logs=1
  # Terminal Ctrl-C hits the whole foreground process group; a lone INT to this script never reaches the
  # backgrounded subshell, so kill it here as a backstop.
  if [[ -n "$child_pid" ]]; then
    kill "$child_pid" 2>/dev/null || true
  fi
  printf '\ninterrupted; logs kept at %s\n' "$logs_dir"
  exit 130
}
trap on_int INT

# Noise reduction: drop nix-update's command echo and upstream probing lines, and the body of nix's
# cached-version warnings; compress Python tracebacks to the final exception line. The remaining lines are
# the node's key log. The same rule set serves both the final summary and the runtime activity line.
filter_stream() {
  grep -vE \
    -e '^\$ ' \
    -e '^fetch ' \
    -e '^using netrc file' \
    -e '^Not updating version' \
    -e '^No changes detected' \
    -e '^warning: unable to download ' \
    -e 'using cached version' \
    -e '^warning: Git tree .* is dirty' \
    -e '^evaluating flake' \
    -e '^checking flake output' \
    -e '^checking derivation' \
    -e '^derivation evaluated to' \
    -e '^traversed ' \
    -e '^emitted ' \
    -e '^formatted ' \
    -e '^response body:' \
    -e '^\{"message":' \
    -e '^Traceback \(most recent call last\):$' \
    -e '^  File "' \
    -e '^    ' \
    -e '^\.\.\.' -
}

filter_log() { filter_stream <"$1" | grep -v '^$' || true; }

show_tail() { filter_log "$1" | tail -n 12 | sed 's/^/  /'; }
show_details() { filter_log "$1" | head -n 8 | sed 's/^/  /'; }

# Compare only the rev/lastModified resolved for root inputs; follows entries are already reflected in their source inputs.
flake_snapshot() {
  jq -r '
    .nodes as $nodes
    | $nodes.root.inputs
    | to_entries[]
    | .key as $name
    | (.value | if type == "array" then .[0] else . end) as $id
    | select(($id | type) == "string" and ($id | startswith("follows") | not))
    | $nodes[$id].locked.rev // $nodes[$id].locked.lastModified // "?"
    | "\($name) \(.)"
  ' flake.lock 2>/dev/null || true
}

update_flake() {
  flake_snapshot >"$logs_dir/flake-lock-before"
  local rc=0
  nix flake update "$@" || rc=$?
  flake_snapshot >"$logs_dir/flake-lock-after"
  return "$rc"
}

# Structured summary for the flake node: join the before/after snapshots by input name and print old→new
# per input; newly added inputs are listed separately; revs truncate to 7 chars and lastModified seconds
# become dates.
flake_change_summary() {
  local before=$1 after=$2 log=$3
  local moved added n desc stale
  moved="$(
    join -j 1 <(sort "$before") <(sort "$after") |
      awk '
        function disp(v) {
          if (v ~ /^[0-9a-f]{40}$/) return substr(v, 1, 7)
          if (v ~ /^[0-9]{10}$/) return strftime("%Y-%m-%d", v, 1)
          return v
        }
        $2 != $3 { printf "  %s %s → %s\n", $1, disp($2), disp($3) }
      '
  )"
  added="$(
    comm -13 <(cut -d' ' -f1 "$before" | sort) <(cut -d' ' -f1 "$after" | sort) |
      sed 's/^/  +/; s/$/ new input/'
  )"
  n=$(grep -c . <<<"$moved" || true)
  n=$((n + $(grep -c . <<<"$added" || true)))
  if ((n > 0)); then desc="$n updated"; else desc="lock unchanged"; fi
  stale="$(grep -c 'using cached version' "$log" || true)"
  if [[ "$stale" =~ ^[0-9]+$ ]] && ((stale > 0)); then
    desc+="; $stale inputs kept cached revisions"
  fi
  printf 'ok (%s)\n' "$desc"
  if [[ -n "$moved" ]]; then printf '%s\n' "$moved"; fi
  if [[ -n "$added" ]]; then printf '%s\n' "$added"; fi
}

# Child output goes to disk and an rc file is written at the end; the render loop uses the rc file as the
# completion signal — kill -0 must not decide liveness (unreaped zombies also pass that probe).
run_logged() {
  local log=$1 rc_file=$2
  shift 2
  local node_rc=0
  "$@" >>"$log" 2>&1 || node_rc=$?
  printf '%d\n' "$node_rc" >"$rc_file"
}

# TTY status line: show a readable log tail when present, else spinner+elapsed; refresh in place.
render_status() {
  local name=$1 log=$2 t0=$3 tag=$4 rc_file=$5
  local frame=0 cols avail line status
  cols=$(tput cols 2>/dev/null || echo 100)
  [[ "$cols" =~ ^[0-9]+$ ]] || cols=100
  ((cols < 20)) && cols=20
  avail=$((cols - ${#name} - 3))
  while kill -0 "$child_pid" 2>/dev/null && [[ ! -s "$rc_file" ]]; do
    line="$(
      tail -c 4096 -- "$log" |
        tr '\r' '\n' |
        filter_stream |
        awk 'NF {l = $0} END {if (l) {gsub(/^[ \t]+|[ \t]+$/, "", l); print l}}' || true
    )"
    status="${spin_frames[frame++ % ${#spin_frames[@]}]} "
    if [[ -n "$line" ]]; then
      status+="$line"
    else
      status+="$((SECONDS - t0))s"
    fi
    if [[ -n "$tag" ]]; then status="$tag$status"; fi
    printf '\r%s: %.*s\e[K' "$name" "$avail" "$status"
    sleep 0.15
  done
}

# run_node <flake|pkg|plain> <display name> <retries> <command…>
run_node() {
  local kind=$1 name=$2 retries=$3
  shift 3
  local log="$logs_dir/$name.log" rc_file="$logs_dir/$name.rc" tries=1 rc=0 i t0 tag
  ((retries > 0)) && tries=2
  ((is_tty)) || printf '%s: ' "$name"
  for ((i = 1; i <= tries; i++)); do
    if ((i > 1)); then
      ((is_tty)) || printf 'retrying '
      sleep 2
    fi
    : >"$log"
    rm -f -- "$rc_file"
    t0=$SECONDS
    tag=""
    if ((i > 1)); then tag="retry $i/$tries "; fi
    run_logged "$log" "$rc_file" "$@" &
    child_pid=$!
    if ((is_tty)); then
      render_status "$name" "$log" "$t0" "$tag" "$rc_file"
    fi
    wait "$child_pid" || true
    child_pid=
    rc=$(cat -- "$rc_file" 2>/dev/null || true)
    rc=${rc:-1}
    if ((rc == 0)); then break; fi
  done
  if ((is_tty)); then printf '\r\e[K%s: ' "$name"; fi
  if ((rc != 0)); then
    printf 'FAILED (exit %d)\n' "$rc"
    show_tail "$log"
    failures+=("$name")
    return 0
  fi
  case $kind in
    flake)
      # nix only warns on nonexistent input names; silently skipping would let a typo produce no update.
      if grep -q "does not match any input of this flake" "$log"; then
        printf 'FAILED (unknown flake input)\n'
        grep -oP "warning: '\K[^']+(?=' does not match)" "$log" | sed 's/^/  /' || true
        failures+=("$name")
        return 0
      fi
      printf '%s\n' "$(flake_change_summary "$logs_dir/flake-lock-before" "$logs_dir/flake-lock-after" "$log")"
      ;;
    pkg)
      local m
      m="$(grep -oP 'Update \K.*(?= in )' "$log" | head -n1 || true)"
      if [[ -z "$m" ]]; then
        m="$(grep -oP 'Not updating version, already \K.*' "$log" | head -n1 || true)"
        if [[ -n "$m" ]]; then m="already $m"; fi
      fi
      printf 'ok%s\n' "${m:+ ($m)}"
      show_details "$log"
      ;;
    *)
      printf 'ok\n'
      show_details "$log"
      ;;
  esac
}

if [[ $mode == "all" ]]; then
  run_node flake "flake lock" 1 update_flake "$@"
fi

while read -r name extra || [[ -n "${name:-}" ]]; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  # shellcheck disable=SC2086
  run_node pkg "$name" 1 nix-update "$name" --flake --format $extra
done < packages/update.list

run_node plain "pi-plugins lock" 1 scripts/sh/sync-pi-plugins-lock.sh
run_node plain "piliplus lock" 1 scripts/sh/sync-piliplus-locks.sh

if [[ $mode == "all" ]]; then
  run_node plain "wechat" 1 scripts/sh/update-wechat.sh
  run_node plain "models" 1 scripts/sh/sync-models.sh
  run_node plain "lint" 0 just repo lint
  run_node plain "test" 0 just repo test
fi

if ((${#failures[@]} > 0)); then
  keep_logs=1
  printf '\nfailed: %s\nfull logs: %s\n' "${failures[*]}" "$logs_dir"
  exit 1
fi
