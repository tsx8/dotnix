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
        (runCommand "pingfang-sc"
          {
            src = requireFile {
              name = "PingFang.ttc";
              sha256 = "6bccdb1a967b2ae7e856927eb559591b2ce05656b0d4ad2764b9c9429f12c0b7";
              message = "Run nix-store --add-fixed sha256 /path/to/PingFang.ttc with the original font file.";
            };
          }
          ''
            install -Dm644 "$src" "$out/share/fonts/truetype/PingFang.ttc"
          ''
        )
        noto-fonts-cjk-sans
        noto-fonts-cjk-serif
      ];

      fontconfig.defaultFonts = {
        sansSerif = [
          "PingFang SC"
          "Noto Sans CJK SC"
        ];
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

  dotnix.modules.home =
    let
      normalFont = "PingFang SC,10,-1,5,400,0,0,0,0,0";
      smallFont = "PingFang SC,8,-1,5,400,0,0,0,0,0";
    in
    {
      # 逐项写入，保留 KDE 管理的主题、颜色及其他设置。
      qt.kde.settings.kdeglobals = {
        General = {
          font = normalFont;
          menuFont = normalFont;
          toolBarFont = normalFont;
          taskbarFont = normalFont;
          smallestReadableFont = smallFont;
        };
        WM.activeFont = normalFont;
      };
    };
}
