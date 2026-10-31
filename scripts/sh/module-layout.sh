#!/usr/bin/env bash
# import-tree imports every .nix file under modules/, so a module and the files it owns
# share one path: either a single <name>.nix or <name>/default.nix. Keeping <name>.nix
# beside <name>/ splits the feature across two sibling paths and leaves the directory
# without an entry point.
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
