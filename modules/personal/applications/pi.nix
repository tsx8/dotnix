{ config, inputs, ... }:
{
  dotnix.modules.nixos =
    { pkgs, ... }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      pi = inputs.llm-agents.packages.${system}.pi;
      adapter = config.flake.packages.${system}.pi-mcp-adapter;
    in
    {
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "pi" ''
          export PATH="${pkgs.bash}/bin:$PATH"
          export BASH_ENV=/etc/direnv/bash-env
          exec ${pi}/bin/pi --extension ${adapter}/node_modules/pi-mcp-adapter/index.ts "$@"
        '')
      ];
    };

  perSystem = { pkgs, ... }: {
    packages.pi-mcp-adapter = pkgs.callPackage ../../../packages/pi-mcp-adapter/package.nix { };
  };
}
