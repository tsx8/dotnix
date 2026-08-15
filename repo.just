fmt:
  nix fmt

check:
  nix flake check --no-build

update:
  nix flake update
  nix flake check --no-build