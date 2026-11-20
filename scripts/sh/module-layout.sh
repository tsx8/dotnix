#!/usr/bin/env bash
set -euo pipefail

repo_root="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"

cd "$repo_root"

status=0
while IFS= read -r path; do
  [[ -e $path ]] || continue
  dir="${path%.nix}"
  [[ -d $dir ]] || continue
  printf '%s: move the module to %s/default.nix\n' "$path" "$dir" >&2
  status=1
done < <(git ls-files '*.nix')

exit "$status"
