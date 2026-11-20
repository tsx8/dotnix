{
  perSystem =
    { pkgs, config, ... }:
    let
      lintPython = pkgs.python3.withPackages (ps: [
        ps.pygments
        ps.unidiff
      ]);
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
          (pkgs.writeShellScriptBin "check-comments" ''
            exec ${lintPython.interpreter} -I ${./comment-check.py} "$@"
          '')
          pkgs.nix-update

          mcpDotnixCli
          mcpNixosCli
        ];
      };
    };
}
