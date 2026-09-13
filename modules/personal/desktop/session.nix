{
  dotnix.modules.nixos = { pkgs, lib, ... }: {
    # 默认使用的是 VF 可变字体，修改为静态字体版，
    # 兼容无法使用可变字体的场景（如 QQ 音乐、腾讯会议等使用 Electron 8 打包的应用）
    nixpkgs.overlays = [
      (_final: prev: {
        noto-fonts-cjk-sans = prev.noto-fonts-cjk-sans.override { static = true; };
        noto-fonts-cjk-serif = prev.noto-fonts-cjk-serif.override { static = true; };
      })
    ];

    fonts = {
      packages = with pkgs; [
        noto-fonts-cjk-sans
        noto-fonts-cjk-serif
      ];

      fontconfig.defaultFonts = {
        sansSerif = lib.mkAfter [ "Noto Sans CJK SC" ];
        serif = lib.mkAfter [ "Noto Serif CJK SC" ];
      };
    };

    services.xserver.enable = true;
    services.displayManager.sddm.enable = true;
    services.desktopManager.plasma6.enable = true;

    security.rtkit.enable = true;

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
  };
}
