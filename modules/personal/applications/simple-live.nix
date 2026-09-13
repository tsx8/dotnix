{ config, ... }:
{
  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = [
      config.flake.packages.${pkgs.stdenv.hostPlatform.system}.simple-live-app
    ];
  };

  perSystem = { pkgs, ... }: {
    packages.simple-live-app = pkgs.callPackage ../../../packages/simple-live-app/package.nix { };
  };
}
