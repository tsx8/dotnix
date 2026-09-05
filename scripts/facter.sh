#!/usr/bin/env bash
set -euo pipefail

NIX_CONFIG="$(printf '%s\n%s\n' \
  "${NIX_CONFIG:-}" \
  'experimental-features = nix-command flakes')"
export NIX_CONFIG

repo_root="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
  pwd
)"

report="$repo_root/facter.json"

cd "$repo_root"

tmp="$(mktemp "$repo_root/.facter.json.XXXXXX")"

cleanup() {
  rm -f "$tmp"
}
trap cleanup EXIT

facter="$(
  nix build \
    --no-link \
    --print-out-paths \
    .#nixos-facter
)/bin/nixos-facter"

sudo "$facter" -o "$tmp"

if [[ ! -s "$tmp" ]]; then
  echo "error: nixos-facter produced an empty report" >&2
  exit 1
fi

mv "$tmp" "$report"
trap - EXIT

echo "Hardware report written to:"
echo "  $report"
echo
git diff --stat -- facter.json
