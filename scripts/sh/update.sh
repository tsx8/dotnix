#!/usr/bin/env bash
set -euo pipefail

# just repo update / pkg-update 的编排入口。单节点失败不中断后续节点，
# 网络类节点失败自动重试一次；末尾汇总失败节点并保留完整日志目录，
# 全部成功时清理日志。TTY 下运行中原地刷新状态行（当前活动尾行，
# 无输出时 spinner+耗时）；非 TTY 退化为静态输出。

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
  # 终端 Ctrl-C 作用于整个前台进程组；脚本被单独 INT 时后台子 shell 收不到，需兜底。
  if [[ -n "$child_pid" ]]; then
    kill "$child_pid" 2>/dev/null || true
  fi
  printf '\ninterrupted; logs kept at %s\n' "$logs_dir"
  exit 130
}
trap on_int INT

# 降噪：去掉 nix-update 的命令回显与上游探测行、nix 沿用缓存版本的告警正文，
# 把 Python traceback 压缩为最终异常行；剩余行即该节点的关键日志。
# 同一组规则用于结束摘要与运行时活动行。
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

# 只比对根输入解析到的 rev/lastModified；follows 指向已在源输入中体现。
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

# flake 节点的结构化摘要：按输入名 join 前后快照，逐输入输出旧→新；
# 新增输入单独列出；rev 截短为 7 位、lastModified 秒值转日期。
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

# 子进程输出落盘并在结束时写 rc 文件；渲染循环以 rc 文件为完成信号，
# 不能用 kill -0 判活（未收割的僵尸进程也能通过探测）。
run_logged() {
  local log=$1 rc_file=$2
  shift 2
  local node_rc=0
  "$@" >>"$log" 2>&1 || node_rc=$?
  printf '%d\n' "$node_rc" >"$rc_file"
}

# TTY 状态行：有可读日志尾行时显示尾行，否则 spinner+耗时；原地刷新。
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

# run_node <flake|pkg|plain> <显示名> <重试次数> <命令…>
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
      # nix 对不存在的输入名只告警不报错，静默跳过会导致拼写错误无更新。
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
