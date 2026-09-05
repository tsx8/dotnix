#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" != "switch" ]; then
  echo "usage: os.sh switch [label]" >&2
  exit 2
fi

label="${2-}"
if [ -z "$label" ]; then
  label="$(dirname "$0")/worktree-label.sh"
  label="$("$label")"
fi

echo "label: $label"
export NIXOS_LABEL="$label"
exec nh os switch --hostname maco --ask --impure --no-update-lock-file --no-write-lock-file .#maco
