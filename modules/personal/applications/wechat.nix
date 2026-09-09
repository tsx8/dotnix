{ inputs, ... }: {
  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = [
      (pkgs.callPackage "${inputs.nixpkgs}/pkgs/by-name/we/wechat/linux.nix" {
        inherit (pkgs.wechat) pname meta;
        version = "4.1.13.9";
        # 腾讯会覆盖此下载地址；升级时须同时核对版本和哈希。
        src = pkgs.fetchurl {
          url = "https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.AppImage";
          hash = "sha256-ay4g5wAGNy6N37rkDqhkVkUgyHsH0BYLYA7JP3j9XMI=";
        };
      })
    ];
  };
}
