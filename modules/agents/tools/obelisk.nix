{ config, ... }:
{
  perSystem = { pkgs, ... }: {
    packages.obelisk = pkgs.callPackage ../../../packages/obelisk/package.nix { };
  };

  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = [
      config.flake.packages.${pkgs.stdenv.hostPlatform.system}.obelisk
    ];
  };
}
