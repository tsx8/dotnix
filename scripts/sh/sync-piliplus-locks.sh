#!/usr/bin/env bash
set -euo pipefail

# From the current version in packages/piliplus/package.nix, rebuild pubspec.lock.json and git-hashes.json
# from the upstream tag; called by just repo pkg-update after nix-update bumps the version.
# Returns immediately when pubspec.lock is unchanged, skipping needless git dependency prefetching.

if [[ $# -ne 0 ]]; then
  echo "usage: $0" >&2
  exit 2
fi

repo_root="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"
pkg_dir="$repo_root/packages/piliplus"

version="$(sed -n 's/^  version = "\([^"]*\)";$/\1/p' "$pkg_dir/package.nix" | head -1)"
if [[ -z "$version" ]]; then
  echo "error: cannot read version from $pkg_dir/package.nix" >&2
  exit 1
fi

lock_tmp="$(mktemp)"
hashes_tmp=""
trap 'rm -f -- "$lock_tmp"; [[ -z "$hashes_tmp" ]] || rm -f -- "$hashes_tmp"' EXIT

curl -fsSL --max-time 60 \
  "https://raw.githubusercontent.com/bggRGjQaUbCoE/PiliPlus/$version/pubspec.lock" \
  | nix shell nixpkgs#yq-go --command \
    yq eval --output-format=json --prettyPrint >"$lock_tmp"

if cmp -s -- "$lock_tmp" "$pkg_dir/pubspec.lock.json"; then
  exit 0
fi

# Take the path from this repo's flake inputs, reusing the locked rev and narHash.
nixpkgs_out="$(cd -- "$repo_root" && nix eval --impure --raw --no-update-lock-file --no-write-lock-file --expr '(builtins.getFlake (toString ./.)).inputs.nixpkgs.outPath')"
hashes_tmp="$(mktemp)"
# nix-prefetch-git resets HOME, breaking agent sessions that rely on BASH_ENV to locate the direnv
# authorization right at script startup.
nix shell nixpkgs#python3 nixpkgs#nix-prefetch-git --command \
  env -u BASH_ENV python3 "$nixpkgs_out/pkgs/development/compilers/dart/fetch-git-hashes.py" \
  --input "$lock_tmp" --output "$hashes_tmp"

mv -- "$lock_tmp" "$pkg_dir/pubspec.lock.json"
mv -- "$hashes_tmp" "$pkg_dir/git-hashes.json"
trap - EXIT
echo "piliplus dependency locks changed for $version; review and rebuild."
