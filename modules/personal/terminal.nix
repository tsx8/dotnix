{ config, ... }:
let
  userName = config.dotnix.host.userName;
in
{
  dotnix.modules.nixos = { pkgs, ... }: {
    programs.fish.enable = true;
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    users.users.${userName}.shell = pkgs.fish;
    # pi 等终端程序复制依赖 wl-copy 访问 Wayland 剪贴板，本机无其他来源提供
    environment.systemPackages = with pkgs; [
      curl
      wget
      jq
      fd
      ripgrep
      wl-clipboard
    ];
  };
  dotnix.modules.home = {
    programs.fish = {
      enable = true;
    };

    # fish 模块默认开启 man 缓存（供 apropos 补全），但 home.packages 不含
    # man pages（仓库原则），mandb 对空目录不产出导致构建失败，显式关闭
    programs.man.generateCaches = false;
  };
}
