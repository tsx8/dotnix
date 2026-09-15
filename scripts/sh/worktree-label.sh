#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM HUP

(
  # 临时 index 纳入未暂存修改和新文件，不改变用户的真实暂存区。
  export GIT_INDEX_FILE="$tmp_dir/index"
  git read-tree HEAD
  git add -A -- .
  git write-tree
) | cut -c1-12
