{ config, ... }:
{
  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = [ config.flake.packages.${pkgs.stdenv.hostPlatform.system}.piliplus ];
  };

  perSystem = { pkgs, ... }: {
    packages.piliplus = pkgs.callPackage ../../../packages/piliplus/package.nix { };
  };
}
