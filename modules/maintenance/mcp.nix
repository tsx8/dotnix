{
  perSystem =
    { pkgs, inputs', ... }:
    {
      packages = {
        mcp-dotnix = pkgs.callPackage ../../packages/mcp-dotnix/package.nix { };

        # 上游查询 flake 输入时调用 nix flake archive，但缺少 lock 保护参数。
        mcp-nixos = inputs'.mcp-nixos.packages.mcp-nixos.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            substituteInPlace mcp_nixos/sources/flake_inputs.py \
              --replace-fail \
                '["flake", "archive", "--json"]' \
                '["flake", "archive", "--json", "--no-update-lock-file", "--no-write-lock-file"]'
          '';
        });
      };
    };
}
