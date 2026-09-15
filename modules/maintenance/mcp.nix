{ config, self, ... }:
let
  userName = config.dotnix.host.userName;
in
{
  dotnix.modules.nixos = { pkgs, ... }: {
    security.sudo.extraRules = [
      {
        users = [ userName ];
        runAs = "root";
        commands = [
          {
            # 免密只匹配不可修改的专用入口；同账户程序也能直接调用它。
            command = "${self.packages.${pkgs.stdenv.hostPlatform.system}.mcp-dotnix.privilegedRunner}";
            options = [
              "NOPASSWD"
              "NOSETENV"
            ];
          }
        ];
      }
    ];
  };

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
