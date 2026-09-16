{ config, inputs, ... }:
{
  perSystem = { pkgs, ... }: {
    packages.wechat = pkgs.callPackage ../../../packages/wechat/package.nix {
      # 复用 nixpkgs 的 AppImage 打包与元数据，只锁定会漂移的 version/src。
      linuxNix = "${inputs.nixpkgs}/pkgs/by-name/we/wechat/linux.nix";
      inherit (pkgs.wechat) pname meta;
    };
  };

  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = [
      config.flake.packages.${pkgs.stdenv.hostPlatform.system}.wechat
    ];
  };
}
