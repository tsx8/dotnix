#!/usr/bin/env bash
set -euo pipefail

trap 'printf "%s\n" "WARN overlays: Check unavailable; overlay impact was not assessed. See docs/development.md#overlay-impact." >&2; exit 0' ERR

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."

changed="$(git diff --name-only --no-renames -z HEAD -- 2>/dev/null | jq -Rsc 'split("\u0000") | map(select(length > 0))' 2>/dev/null)"
[[ $changed != '[]' ]] || exit 0

sources="$(
  timeout 15s nix eval --impure --offline --json \
    --no-update-lock-file --no-write-lock-file \
    --option allow-import-from-derivation false \
    --expr '
      let
        flake = builtins.getFlake (toString ./.);
        lib = flake.inputs.nixpkgs.lib;
        prefix = toString flake.outPath + "/";
        definitions = flake.nixosConfigurations.maco.options.nixpkgs.overlays.definitionsWithLocations;
        # Deferred modules append option context to their source locations.
        sources = map (definition: builtins.head (lib.splitString ", via option " definition.file))
          (builtins.filter (definition: builtins.length definition.value > 0) definitions);
      in
        map (lib.removePrefix prefix) (builtins.filter (lib.hasPrefix prefix) sources)
    ' 2>/dev/null
)"

summary="$(
  jq -r --argjson changed "$changed" '
    [.[] | select(. as $source | $changed | index($source))] | unique |
    if length == 0 then empty else
      (.[0:3] | map(@json) | join(", ")) +
      (if length > 3 then " (+\(length - 3) more)" else "" end)
    end
  ' <<<"$sources" 2>/dev/null
)"

if [[ -n $summary ]]; then
  printf 'WARN overlays: Changed modules contribute global overlays: %s.\n' "$summary" >&2
  printf '%s\n' 'INFO overlays: Dependent derivations may change. See docs/development.md#overlay-impact for a controlled comparison.' >&2
fi
