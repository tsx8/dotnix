{ config, ... }:
{
  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = [
      config.flake.packages.${pkgs.stdenv.hostPlatform.system}.obelisk
    ];
  };

  perSystem = { pkgs, ... }: {
    packages.obelisk = pkgs.callPackage ../../../packages/obelisk/package.nix { };
  };
}
