#!/usr/bin/env bash
set -euo pipefail

# just repo update / pkg-update 的编排入口。单节点失败不中断后续节点，
# 网络类节点失败自动重试一次；末尾汇总失败节点并保留完整日志目录，
# 全部成功时清理日志。

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
cleanup() { ((keep_logs)) || rm -rf -- "$logs_dir"; }
trap cleanup EXIT
trap 'keep_logs=1; printf "\ninterrupted; logs kept at %s\n" "$logs_dir"; exit 130' INT

# 降噪：去掉 nix-update 的命令回显与上游探测行、nix 沿用缓存版本的告警正文，
# 把 Python traceback 压缩为最终异常行；剩余行即该节点的关键日志。
filter_log() {
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
    -e '^\.\.\.' \
    "$1" | grep -v '^$' || true
}

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

# run_node <flake|pkg|plain> <显示名> <重试次数> <命令…>
run_node() {
  local kind=$1 name=$2 retries=$3
  shift 3
  local log="$logs_dir/$name.log" tries=1 rc=0 i
  ((retries > 0)) && tries=2
  printf '%s: ' "$name"
  for ((i = 1; i <= tries; i++)); do
    if ((i > 1)); then
      printf 'retrying '
      sleep 2
    fi
    : >"$log"
    if "$@" >>"$log" 2>&1; then
      rc=0
      break
    fi
    rc=$?
  done
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
      local changed desc stale
      changed="$(
        comm -13 <(sort "$logs_dir/flake-lock-before") <(sort "$logs_dir/flake-lock-after") |
          cut -d' ' -f1 | paste -sd, -
      )"
      if [[ -n "$changed" ]]; then desc="updated: $changed"; else desc="lock unchanged"; fi
      stale="$(grep -c 'using cached version' "$log" || true)"
      if [[ "$stale" =~ ^[0-9]+$ ]] && ((stale > 0)); then
        desc+="; $stale inputs kept cached revisions"
      fi
      printf 'ok (%s)\n' "$desc"
      ;;
    pkg)
      local m
      m="$(grep -oP 'Update \K.*(?= in )' "$log" | head -n1 || true)"
      if [[ -z "$m" ]]; then
        m="$(grep -oP 'Not updating version, already \K.*' "$log" | head -n1 || true)"
        [[ -n "$m" ]] && m="already $m"
      fi
      printf 'ok%s\n' "${m:+ ($m)}"
      ;;
    *)
      printf 'ok\n'
      ;;
  esac
  show_details "$log"
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
