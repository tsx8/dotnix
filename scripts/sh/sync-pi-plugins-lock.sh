#!/usr/bin/env bash
set -euo pipefail

# 按 packages/pi-plugins/package.nix 的当前版本，从 npm 重建合成 package.json
# 与依赖 lock；被 just repo pkg-update 在 nix-update 更新版本后调用。

if [[ $# -ne 0 ]]; then
  echo "usage: $0" >&2
  exit 2
fi

repo_root="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"
pkg_dir="$repo_root/packages/pi-plugins"

version="$(sed -n 's/^  version = "\([^"]*\)";$/\1/p' "$pkg_dir/package.nix" | head -1)"
if [[ -z "$version" ]]; then
  echo "error: cannot read version from $pkg_dir/package.nix" >&2
  exit 1
fi

deps="$(npm view "@nklisch/pi-plugins@$version" dependencies --json)"
if ! jq -e 'type == "object" and length > 0' >/dev/null <<<"$deps"; then
  echo "error: npm registry returned no dependencies for @nklisch/pi-plugins@$version" >&2
  exit 1
fi

# 只锁定主入口 dist/pi/extension.js 的运行时闭包；pi-subagents/jiti 仅供
# 未注入的可选入口，不入清单。
adapter="$(jq -r '.["@nklisch/pi-mcp-adapter"] // empty' <<<"$deps")"
if [[ -z "$adapter" ]]; then
  echo "error: @nklisch/pi-plugins@$version no longer depends on @nklisch/pi-mcp-adapter" >&2
  exit 1
fi

jq -n --arg version "$version" --arg adapter "$adapter" '{
  name: "@nklisch/pi-plugins",
  version: $version,
  private: true,
  description: "Synthesized runtime closure manifest for the pi plugin host extension",
  dependencies: {
    "@nklisch/pi-mcp-adapter": $adapter
  }
}' > "$pkg_dir/package.json"

manifest_baseline="$(mktemp)"
lock_baseline="$(mktemp)"
cp -- "$pkg_dir/package.json" "$manifest_baseline"
cp -- "$pkg_dir/package-lock.json" "$lock_baseline"
(cd -- "$pkg_dir" && npm install --package-lock-only --ignore-scripts >/dev/null)

if ! cmp -s -- "$manifest_baseline" "$pkg_dir/package.json" ||
  ! cmp -s -- "$lock_baseline" "$pkg_dir/package-lock.json"; then
  echo "pi-plugins dependency manifest changed for $version; review and commit the regenerated files."
fi
rm -f -- "$manifest_baseline" "$lock_baseline"
