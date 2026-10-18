#!/usr/bin/env bash
set -euo pipefail

NIX_CONFIG="$(printf '%s\n%s\n' \
  "${NIX_CONFIG:-}" \
  'experimental-features = nix-command flakes')"
export NIX_CONFIG

if [[ $# -ne 1 || ( "$1" != system && "$1" != data ) ]]; then
  echo "usage: $0 <system|data>" >&2
  exit 2
fi

role="$1"
root_mount=/mnt
if [[ "$role" == data ]]; then
  root_mount=/mnt-data
fi

repo_root="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"

cd "$repo_root"

device="$(
  nix eval --no-update-lock-file --no-write-lock-file --raw \
    .#diskoConfigurations --apply "
      configs:
      if !builtins.hasAttr \"$role\" configs then
        throw \"Storage role $role is not configured\"
      else
        let disks = configs.$role.disko.devices.disk; in
        assert builtins.attrNames disks == [ \"$role\" ];
        disks.$role.device
    "
)"

configured_device="$(
  nix eval --no-update-lock-file --no-write-lock-file --raw \
    ".#nixosConfigurations.maco.config.disko.devices.disk.$role.device"
)"

if [[ "$configured_device" != "$device" ]]; then
  echo "error: operation and runtime configurations disagree for $role" >&2
  exit 1
fi

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

if [[ "$device_type" != disk ]]; then
  echo "error: target must be a whole disk, not a partition" >&2
  echo "resolved target: $real_device ($device_type)" >&2
  exit 1
fi

# disko unmounts the operation root recursively; another disk must not get mixed into it.
mounts="$(findmnt --noheadings --raw --output TARGET,SOURCE)"
while read -r mountpoint source; do
  if [[ "$mountpoint" != "$root_mount" && "$mountpoint" != "$root_mount/"* ]]; then
    continue
  fi
  source="${source%%\[*}"
  if [[ ! -b "$source" ]]; then
    echo "error: unrelated mount under $root_mount: $mountpoint" >&2
    exit 1
  fi
  parent="$(lsblk -dnro PKNAME "$(realpath "$source")")"
  if [[ "$(realpath "$source")" != "$real_device" &&
        ( -z "$parent" || "$(realpath "/dev/$parent")" != "$real_device" ) ]]; then
    echo "error: $mountpoint belongs to a different disk" >&2
    exit 1
  fi
done <<< "$mounts"

echo
echo "Target disk ($role):"
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

disko="$(
  nix build \
    --no-link \
    --no-update-lock-file \
    --no-write-lock-file \
    --print-out-paths \
    .#disko
)/bin/disko"

echo
echo "Starting Disko..."
echo

sudo "$disko" \
  --mode destroy,format,mount \
  --root-mountpoint "$root_mount" \
  --flake ".#$role"
