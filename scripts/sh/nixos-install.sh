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

require_mount() {
  local path="$1"

  if ! findmnt --mountpoint "$path" >/dev/null 2>&1; then
    echo "error: $path is not mounted" >&2
    echo "run scripts/sh/disk.sh first" >&2
    exit 1
  fi
}

require_mount /mnt
require_mount /mnt/boot
require_mount /mnt/home
require_mount /mnt/nix

configured_device="$(
  nix eval --raw \
    .#nixosConfigurations.maco.config.disko.devices.disk.main.device
)"

if [[ "$configured_device" == *REPLACE-ME* ]]; then
  echo "error: modules/machine/storage/disk-device.data.nix still contains the placeholder device" >&2
  echo "run scripts/sh/disk.sh first" >&2
  exit 1
fi

if [[ ! -L "$configured_device" || ! -b "$configured_device" ]]; then
  echo "error: configured disk is not a valid block-device symlink:" >&2
  echo "  $configured_device" >&2
  exit 1
fi

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
