#!/usr/bin/env bash
set -euo pipefail

# 按 packages/piliplus/package.nix 的当前版本，从上游 tag 重建 pubspec.lock.json
# 与 git-hashes.json；被 just repo pkg-update 在 nix-update 更新版本后调用。
# pubspec.lock 未变化时直接返回，避免无谓的 git 依赖预取。

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
trap 'rm -f -- "$lock_tmp"' EXIT

curl -fsSL --max-time 60 \
  "https://raw.githubusercontent.com/bggRGjQaUbCoE/PiliPlus/$version/pubspec.lock" \
  | nix shell nixpkgs#yq-go --command \
    yq eval --output-format=json --prettyPrint >"$lock_tmp"

if cmp -s -- "$lock_tmp" "$pkg_dir/pubspec.lock.json"; then
  exit 0
fi

# 哈希脚本与构建侧使用同一份锁定 nixpkgs，保证预取口径一致。
nixpkgs_out="$(nix eval --raw --no-update-lock-file "$repo_root#inputs.nixpkgs.outPath")"
hashes_tmp="$(mktemp)"
nix shell nixpkgs#python3 nixpkgs#nix-prefetch-git --command \
  python3 "$nixpkgs_out/pkgs/development/compilers/dart/fetch-git-hashes.py" \
  --input "$lock_tmp" --output "$hashes_tmp"

mv -- "$lock_tmp" "$pkg_dir/pubspec.lock.json"
mv -- "$hashes_tmp" "$pkg_dir/git-hashes.json"
trap - EXIT
echo "piliplus dependency locks changed for $version; review and rebuild."
