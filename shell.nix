{
  mkShell,
  just,
  nh,
  nixfmt-tree,
  nixfmt,
  nixf-diagnose,
  statix,
  shellcheck,
  writeShellScriptBin,
  mcpDotnix,
  mcpNixos,
}:

let
  # 两个 Python 应用依赖互不兼容的 mcp；直接加入会向整个 shell 传播 PYTHONPATH。
  mcpDotnixCli = writeShellScriptBin "mcp-dotnix" ''
    unset PYTHONPATH
    exec "${mcpDotnix}/bin/mcp-dotnix" "$@"
  '';
  mcpNixosCli = writeShellScriptBin "mcp-nixos" ''
    unset PYTHONPATH
    exec "${mcpNixos}/bin/mcp-nixos" "$@"
  '';
in
mkShell {
  packages = [
    just
    nh

    nixfmt-tree
    nixfmt
    nixf-diagnose
    statix
    shellcheck

    mcpDotnixCli
    mcpNixosCli
  ];

}
