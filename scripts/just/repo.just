set working-directory := "../.."

fmt:
  nix fmt

lint:
  @git ls-files -z -- '*.nix' | xargs -0 -r nix fmt -- --no-cache --fail-on-change
  @git ls-files -z -- '*.nix' | xargs -0 -r nix run .#nixf-diagnose --
  @statix check --config modules/maintenance/development/statix.toml
  @git ls-files -z -- 'scripts/sh/*.sh' | xargs -0 -r shellcheck
  @git diff --check HEAD

test:
  nix flake check --no-update-lock-file --no-write-lock-file

update *inputs:
  @bash -euo pipefail -c 'if (($# == 0)); then nix flake update; else nix flake update "$@"; fi; scripts/sh/sync-models.sh; just repo lint; just repo test' update {{inputs}}
