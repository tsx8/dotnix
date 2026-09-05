#!/usr/bin/env bash
set -euo pipefail

NIX_CONFIG="$(printf '%s\n%s\n' \
  "${NIX_CONFIG:-}" \
  'experimental-features = nix-command flakes')"
export NIX_CONFIG

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /dev/disk/by-id/<device>" >&2
  exit 2
fi

device="$1"

repo_root="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
  pwd
)"

cd "$repo_root"

if [[ "$device" != /dev/disk/by-id/* ]]; then
  echo "error: device must use a persistent /dev/disk/by-id/... path" >&2
  exit 1
fi

if [[ ! -L "$device" || ! -b "$device" ]]; then
  echo "error: not a valid block-device symlink: $device" >&2
  exit 1
fi

real_device="$(realpath "$device")"
device_type="$(lsblk -dnro TYPE "$real_device")"

if [[ "$device_type" != "disk" ]]; then
  echo "error: target must be a whole disk, not a partition" >&2
  echo "resolved target: $real_device ($device_type)" >&2
  exit 1
fi

echo
echo "Target disk:"
echo "  persistent path: $device"
echo "  resolved path:   $real_device"
echo

lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL,SERIAL "$real_device"

echo
echo "WARNING: ALL DATA ON THIS DISK WILL BE DESTROYED."
echo
read -r -p "Type the full persistent path to confirm: " confirmation

if [[ "$confirmation" != "$device" ]]; then
  echo "aborted"
  exit 1
fi

tmp="$(mktemp "$repo_root/.disk-device.nix.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

printf '"%s"\n' "$device" > "$tmp"
mv "$tmp" "$repo_root/disk-device.nix"
trap - EXIT

configured_device="$(
  nix eval --raw \
    .#nixosConfigurations.maco.config.disko.devices.disk.main.device
)"

if [[ "$configured_device" != "$device" ]]; then
  echo "error: NixOS configuration did not resolve to the selected disk" >&2
  echo "expected: $device" >&2
  echo "actual:   $configured_device" >&2
  exit 1
fi

disko="$(
  nix build \
    --no-link \
    --print-out-paths \
    .#disko
)/bin/disko"

echo
echo "Starting Disko..."
echo

sudo "$disko" \
  --mode destroy,format,mount \
  --flake ".#maco"
