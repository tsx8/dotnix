{
  perSystem =
    { pkgs, config, ... }:
    let
      # 两个 Python 应用依赖互不兼容的 mcp；直接加入会向整个 shell 传播 PYTHONPATH。
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

          mcpDotnixCli
          mcpNixosCli
        ];
      };
    };
}
