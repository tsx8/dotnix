#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" != "switch" ]; then
  echo "usage: os.sh switch [label]" >&2
  exit 2
fi

repo_root="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"
cd "$repo_root"

label="${2-}"
if [ -z "$label" ]; then
  label="$("$repo_root/scripts/sh/worktree-label.sh")"
fi

echo "label: $label"
export NIXOS_LABEL="$label"
# NixOS 从环境读取自定义 label，纯求值会屏蔽该变量。
exec nh os switch --hostname maco --ask --impure --no-update-lock-file --no-write-lock-file .#maco
