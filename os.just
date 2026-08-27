build:
  nixos-rebuild build --flake .#maco --no-link

test:
  sudo nixos-rebuild test --flake .#maco

switch label="":
  @if [ -n "{{label}}" ]; then L="{{label}}"; else L="$(git write-tree | cut -c1-7)"; fi; echo "label: $L"; sudo NIXOS_LABEL="$L" nixos-rebuild switch --impure --flake .#maco
