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
hashes_tmp=""
trap 'rm -f -- "$lock_tmp"; [[ -z "$hashes_tmp" ]] || rm -f -- "$hashes_tmp"' EXIT

curl -fsSL --max-time 60 \
  "https://raw.githubusercontent.com/bggRGjQaUbCoE/PiliPlus/$version/pubspec.lock" \
  | nix shell nixpkgs#yq-go --command \
    yq eval --output-format=json --prettyPrint >"$lock_tmp"

if cmp -s -- "$lock_tmp" "$pkg_dir/pubspec.lock.json"; then
  exit 0
fi

# 从本仓库的 flake 输入取路径，沿用锁定的 rev 和 narHash。
nixpkgs_out="$(cd -- "$repo_root" && nix eval --impure --raw --no-update-lock-file --no-write-lock-file --expr '(builtins.getFlake (toString ./.)).inputs.nixpkgs.outPath')"
hashes_tmp="$(mktemp)"
# nix-prefetch-git 重置 HOME，导致依赖 BASH_ENV 定位 direnv 授权的代理会话在脚本启动时失败。
nix shell nixpkgs#python3 nixpkgs#nix-prefetch-git --command \
  env -u BASH_ENV python3 "$nixpkgs_out/pkgs/development/compilers/dart/fetch-git-hashes.py" \
  --input "$lock_tmp" --output "$hashes_tmp"

mv -- "$lock_tmp" "$pkg_dir/pubspec.lock.json"
mv -- "$hashes_tmp" "$pkg_dir/git-hashes.json"
trap - EXIT
echo "piliplus dependency locks changed for $version; review and rebuild."
