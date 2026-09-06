fmt:
  nix fmt

lint:
  @git ls-files -z -- '*.nix' | xargs -0 -r nix fmt -- --no-cache --fail-on-change
  @git ls-files -z -- '*.nix' | xargs -0 -r nix run .#nixf-diagnose --
  @statix check --config statix.toml
  @git ls-files -z -- 'scripts/*.sh' | xargs -0 -r shellcheck
  @git diff --check HEAD

test:
  nix flake check --no-update-lock-file --no-write-lock-file

update *inputs:
  @bash -euo pipefail -c 'if (($# == 0)); then nix flake update; else nix flake update "$@"; fi; scripts/sync-models.sh; just repo lint; just repo test' update {{inputs}}
