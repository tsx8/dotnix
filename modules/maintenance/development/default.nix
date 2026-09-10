{
  perSystem =
    { pkgs, config, ... }:
    let
      # 两个应用使用独立的 Python 依赖，只暴露命令以免向整个 shell 传播 PYTHONPATH。
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
