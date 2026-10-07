{ config, self, ... }:
let
  userName = config.dotnix.host.userName;
in
{
  dotnix.modules.nixos = { pkgs, ... }: {
    security.polkit = {
      enable = true;
      enablePkexecWrapper = true;
      extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id === "org.freedesktop.policykit.exec" &&
              action.lookup("program") === ${builtins.toJSON "${self.packages.${pkgs.stdenv.hostPlatform.system}.mcp-dotnix.privilegedRunner}"}) {
            if (subject.user === ${builtins.toJSON userName} && action.lookup("user") === "root") {
              // 授权缓存不区分命令参数，不能使用 AUTH_ADMIN_KEEP。
              return polkit.Result.AUTH_ADMIN;
            }
            return polkit.Result.NO;
          }
        });
      '';
    };
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
