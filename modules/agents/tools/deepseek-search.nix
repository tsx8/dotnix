{ config, ... }:
{
  perSystem = { pkgs, ... }: {
    packages.mcp-deepseek-search =
      pkgs.callPackage ../../../packages/mcp-deepseek-search/package.nix
        { };
  };

  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = [
      config.flake.packages.${pkgs.stdenv.hostPlatform.system}.mcp-deepseek-search
    ];
  };
}
