fmt:
  nix fmt

lint:
  git ls-files -z -- '*.nix' | xargs -0 nix run .#nixf-diagnose --

check: lint
  nix flake check --no-build

update:
  nix flake update
  nix flake check --no-build
