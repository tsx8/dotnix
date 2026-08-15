build:
  sudo nixos-rebuild build --flake .#maco

test:
  sudo nixos-rebuild test --flake .#maco

switch:
  sudo nixos-rebuild switch --flake .#maco