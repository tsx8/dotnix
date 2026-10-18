#!/usr/bin/env bash
set -euo pipefail

# Tencent's WeChat Linux AppImage lives at a versionless rolling URL whose content is silently overwritten.
# Use the Last-Modified header as the change sentinel: no change is a no-op; on change, fetch the
# authoritative hash via the nix channel (bytes from proxied paths are untrusted), read the three-part
# version from the official page, and rewrite version/hash and the recorded line below in
# packages/wechat/package.nix.

if [[ $# -ne 0 ]]; then
  echo "usage: $0" >&2
  exit 2
fi

repo_root="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"
pkg="$repo_root/packages/wechat/package.nix"
url="https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.AppImage"
page="https://linux.weixin.qq.com/"

current="$(curl -fsSI --max-time 30 "$url" | tr -d '\r' | sed -n 's/^Last-Modified: //p' | head -1)"
if [[ -z "$current" ]]; then
  echo "error: no Last-Modified header from $url" >&2
  exit 1
fi
recorded="$(sed -n 's/^# last-modified: //p' "$pkg" | head -1)"
if [[ -z "$recorded" ]]; then
  echo "error: no recorded last-modified line in $pkg" >&2
  exit 1
fi
if [[ "$current" == "$recorded" ]]; then
  exit 0
fi

version="$(curl -fsSL --max-time 30 "$page" | grep -oP 'version" data-v-[0-9a-f]+>\K[0-9]+(\.[0-9]+){2}' | head -1)"
if [[ -z "$version" ]]; then
  echo "error: cannot read current WeChat version from $page" >&2
  exit 1
fi

hash="$(nix store prefetch-file --hash-type sha256 --json "$url" | jq -r '.hash')"
if [[ -z "$hash" || "$hash" == "null" ]]; then
  echo "error: cannot fetch authoritative hash for $url" >&2
  exit 1
fi

for pattern in '^# last-modified: ' '^  version = "' '^    hash = "'; do
  if ! grep -qE "$pattern" "$pkg"; then
    echo "error: $pkg does not contain expected line: $pattern" >&2
    exit 1
  fi
done

candidate="$(mktemp "$pkg.XXXXXX")"
trap 'rm -f -- "$candidate"' EXIT
sed \
  -e "s|^# last-modified: .*|# last-modified: $current|" \
  -e "s|^  version = \"[^\"]*\";|  version = \"$version\";|" \
  -e "s|^    hash = \"[^\"]*\";|    hash = \"$hash\";|" \
  "$pkg" > "$candidate"
mv -- "$candidate" "$pkg"
trap - EXIT
echo "wechat: $recorded -> $current (version $version)"
