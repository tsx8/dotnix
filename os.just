build:
  nixos-rebuild build --flake .#maco --no-link

test:
  sudo nixos-rebuild test --flake .#maco

switch:
  sudo nixos-rebuild switch --flake .#maco
