{
  perSystem =
    { pkgs, config, ... }:
    let
      # The two apps have separate Python dependencies; only their commands are exposed so PYTHONPATH does not leak into the whole shell.
      mcpDotnixCli = pkgs.writeShellScriptBin "mcp-dotnix" ''
        unset PYTHONPATH
        exec "${config.packages.mcp-dotnix}/bin/mcp-dotnix" "$@"
      '';
      mcpNixosCli = pkgs.writeShellScriptBin "mcp-nixos" ''
        unset PYTHONPATH
        exec "${config.packages.mcp-nixos}/bin/mcp-nixos" "$@"
      '';
    in
    {
      formatter = pkgs.nixfmt-tree;

      packages = {
        inherit (pkgs) nixf-diagnose nixos-install;
      };

      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.just
          pkgs.nh

          pkgs.nixfmt-tree
          pkgs.nixfmt
          pkgs.nixf-diagnose
          pkgs.statix
          pkgs.shellcheck
          pkgs.nix-update

          mcpDotnixCli
          mcpNixosCli
        ];
      };
    };
}
