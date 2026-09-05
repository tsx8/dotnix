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
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
  pwd
)"

cd "$repo_root"

if ! mountpoint -q /mnt; then
  echo "error: /mnt is not mounted" >&2
  echo "run scripts/disk.sh first" >&2
  exit 1
fi

for file in recovery-key.age secrets.yaml .sops.yaml; do
  if [[ ! -f "$file" ]]; then
    echo "error: missing $file" >&2
    exit 1
  fi
done

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

if [[ ! -d "$runtime_dir" || ! -w "$runtime_dir" ]]; then
  echo "error: no writable runtime directory: $runtime_dir" >&2
  exit 1
fi

tmp_dir="$(mktemp -d "$runtime_dir/dotnix-secrets.XXXXXX")"
chmod 0700 "$tmp_dir"

recovery_identity="$tmp_dir/recovery-key.txt"
backup_config="$tmp_dir/sops.yaml.backup"
backup_secrets="$tmp_dir/secrets.yaml.backup"
verify_home="$tmp_dir/home"

mkdir -m 0700 "$verify_home"

cp -p .sops.yaml "$backup_config"
cp -p secrets.yaml "$backup_secrets"

machine_key="/mnt/var/lib/sops-nix/key.txt"
created_machine_key=false
committed=false

cleanup() {
  status=$?

  trap - EXIT INT TERM

  if [[ "$status" -ne 0 && "$committed" != true ]]; then
    echo
    echo "error: secrets bootstrap failed; restoring repository files" >&2

    cp -p "$backup_config" .sops.yaml
    cp -p "$backup_secrets" secrets.yaml

    if [[ "$created_machine_key" == true ]]; then
      sudo rm -f "$machine_key"
    fi
  fi

  rm -rf "$tmp_dir"
  exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

age_package="$(
  nix build \
    --no-link \
    --print-out-paths \
    .#age
)"

sops_package="$(
  nix build \
    --no-link \
    --print-out-paths \
    .#sops
)"

age="$age_package/bin/age"
age_keygen="$age_package/bin/age-keygen"
sops="$sops_package/bin/sops"

sudo install -d \
  -o root \
  -g root \
  -m 0700 \
  "$(dirname "$machine_key")"

if sudo test -e "$machine_key"; then
  if ! sudo test -s "$machine_key"; then
    echo "error: existing machine identity is empty: $machine_key" >&2
    exit 1
  fi

  echo "Reusing existing machine identity:"
  echo "  $machine_key"
else
  echo "Generating machine identity:"
  echo "  $machine_key"

  sudo "$age_keygen" -o "$machine_key"
  sudo chown root:root "$machine_key"
  sudo chmod 0600 "$machine_key"

  created_machine_key=true
fi

mapfile -t machine_recipients < <(
  sudo "$age_keygen" -y "$machine_key"
)

if [[ "${#machine_recipients[@]}" -ne 1 ]]; then
  echo "error: expected exactly one machine recipient" >&2
  exit 1
fi

machine_recipient="${machine_recipients[0]}"

echo
echo "Decrypting recovery identity."
echo "Enter the recovery passphrase when prompted."
echo

umask 077
"$age" -d recovery-key.age > "$recovery_identity"

mapfile -t recovery_recipients < <(
  "$age_keygen" -y "$recovery_identity"
)

if [[ "${#recovery_recipients[@]}" -ne 1 ]]; then
  echo "error: expected exactly one recovery recipient" >&2
  exit 1
fi

recovery_recipient="${recovery_recipients[0]}"

cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: ^secrets\\.yaml$
    age: >-
      $recovery_recipient,
      $machine_recipient
EOF

echo
echo "Updating SOPS recipients..."

HOME="$verify_home" \
SOPS_AGE_KEY_FILE="$recovery_identity" \
  "$sops" \
    --config "$repo_root/.sops.yaml" \
    updatekeys -y secrets.yaml

echo
echo "Verifying recovery identity..."

HOME="$verify_home" \
SOPS_AGE_KEY_FILE="$recovery_identity" \
  "$sops" decrypt secrets.yaml >/dev/null

echo "Verifying machine identity..."

sudo env \
  HOME="$verify_home" \
  SOPS_AGE_KEY_FILE="$machine_key" \
  "$sops" decrypt "$repo_root/secrets.yaml" >/dev/null

committed=true

echo
echo "Secrets bootstrap complete."
echo
echo "Machine recipient:"
echo "  $machine_recipient"
echo
echo "Both recovery and machine identities can decrypt secrets.yaml."
echo
git status --short -- .sops.yaml secrets.yaml
