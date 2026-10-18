{ config, ... }:
{
  perSystem = { pkgs, ... }: {
    packages.bex = pkgs.callPackage ../../../packages/bex/package.nix { };
  };

  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = [
      # bex endpoint pinning: overriding exports so that rewriting the environment inside a session cannot
      # point bex at another browser; the helium-use skill declares this endpoint as the only authorized browser.
      (pkgs.writeShellScriptBin "bex" ''
        export BU_CDP_URL=http://127.0.0.1:9222
        export BU_CDP_LAUNCH=helium
        exec ${config.flake.packages.${pkgs.stdenv.hostPlatform.system}.bex}/bin/bex "$@"
      '')
    ];
  };
}
