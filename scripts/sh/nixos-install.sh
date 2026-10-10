#!/usr/bin/env bash
set -euo pipefail

NIX_CONFIG="$(printf '%s\n%s\n' \
  "${NIX_CONFIG:-}" \
  'experimental-features = nix-command flakes')"
export NIX_CONFIG

if [[ $# -ne 0 ]]; then
  echo "usage: $0" >&2
  exit 2
fi

repo_root="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"

cd "$repo_root"

configured_device="$(
  nix eval --no-update-lock-file --no-write-lock-file --raw \
    .#nixosConfigurations.maco.config.disko.devices.disk.system.device
)"

if [[ "$configured_device" != /dev/disk/by-id/* || ! -L "$configured_device" || ! -b "$configured_device" ]]; then
  echo "error: configure a valid system disk in modules/machine/storage/layout.data.nix" >&2
  exit 1
fi

real_device="$(realpath "$configured_device")"
if [[ "$(lsblk -dnro TYPE "$real_device")" != disk ]]; then
  echo "error: the system role must refer to a whole disk" >&2
  exit 1
fi

require_mount() {
  local path="$1" expected_device="$2" expected_root="$3" expected_type="$4"
  local source parent

  if ! source="$(findmnt --mountpoint "$path" --noheadings --raw --output SOURCE)"; then
    echo "error: $path is not mounted; run scripts/sh/disk.sh system first" >&2
    exit 1
  fi
  source="${source%%\[*}"

  if [[ ! -b "$expected_device" || ! -b "$source" || "$(realpath "$source")" != "$(realpath "$expected_device")" ]]; then
    echo "error: $path is not mounted from $expected_device" >&2
    exit 1
  fi

  parent="$(lsblk -dnro PKNAME "$(realpath "$expected_device")")"
  if [[ -z "$parent" || "$(realpath "/dev/$parent")" != "$real_device" ]]; then
    echo "error: $path is not on the configured system disk" >&2
    exit 1
  fi

  if [[ "$(findmnt --mountpoint "$path" --noheadings --raw --output FSROOT)" != "$expected_root" ||
        "$(findmnt --mountpoint "$path" --noheadings --raw --output FSTYPE)" != "$expected_type" ]]; then
    echo "error: $path has the wrong filesystem or subvolume" >&2
    exit 1
  fi
}

root_device="$(
  nix eval --no-update-lock-file --no-write-lock-file --raw \
    '.#nixosConfigurations.maco.config.fileSystems."/".device'
)"
boot_device="$(
  nix eval --no-update-lock-file --no-write-lock-file --raw \
    '.#nixosConfigurations.maco.config.fileSystems."/boot".device'
)"

require_mount /mnt "$root_device" /@root btrfs
require_mount /mnt/home "$root_device" /@home btrfs
require_mount /mnt/nix "$root_device" /@nix btrfs
require_mount /mnt/boot "$boot_device" / vfat

facter_enabled="$(
  nix eval \
    .#nixosConfigurations.maco.config.hardware.facter.enable
)"

if [[ "$facter_enabled" != "true" ]]; then
  echo "error: hardware Facter report is not enabled" >&2
  echo "run scripts/sh/facter.sh first" >&2
  exit 1
fi

machine_key="/mnt/var/lib/sops-nix/key.txt"

if ! sudo test -s "$machine_key"; then
  echo "error: machine SOPS identity is missing or empty:" >&2
  echo "  $machine_key" >&2
  echo "run scripts/sh/secrets.sh first" >&2
  exit 1
fi

key_owner="$(
  sudo stat -c '%U' "$machine_key"
)"

if [[ "$key_owner" != "root" ]]; then
  echo "error: machine SOPS identity must be owned by root" >&2
  exit 1
fi

key_mode="$(
  sudo stat -c '%a' "$machine_key"
)"

case "$key_mode" in
  600|440)
    ;;
  *)
    echo "error: unexpected machine identity permissions: $key_mode" >&2
    echo "expected 600 during installation or 440 after system activation" >&2
    exit 1
    ;;
esac

sops="$(
  nix build \
    --no-link \
    --print-out-paths \
    .#sops
)/bin/sops"

echo "Verifying machine identity can decrypt secrets.yaml..."

sudo env \
  HOME=/root \
  SOPS_AGE_KEY_FILE="$machine_key" \
  "$sops" --config "$repo_root/modules/machine/identity/.sops.yaml" \
  decrypt "$repo_root/modules/machine/identity/secrets.yaml" >/dev/null

nixos_install="$(
  nix build \
    --no-link \
    --print-out-paths \
    .#nixos-install
)/bin/nixos-install"

echo
echo "Installing NixOS..."
echo

sudo "$nixos_install" \
  --root /mnt \
  --flake "$repo_root#maco" \
  --no-channel-copy \
  --no-root-password
