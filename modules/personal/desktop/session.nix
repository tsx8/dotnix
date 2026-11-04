{
  dotnix.modules.nixos = { pkgs, lib, ... }: {
    fonts = {
      # Noto's upstream default is VF variable fonts; register the static builds instead for apps
      # that cannot use them (e.g. QQ Music and Tencent Meeting, built on Electron 8). The override
      # must stay at this consumption site: a global overlay flips the font drv, and fonts.conf
      # embeds font store paths, so poppler and the whole KDE closure would diverge from the
      # binary cache and force repeated local rebuilds of the entire stack.
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
            # Keep a store reference to the original font so the system closure protects the build input from GC.
            install -d "$out/share/fonts/truetype"
            ln -s "$src" "$out/share/fonts/truetype/PingFang.ttc"
          ''
        )
        (noto-fonts-cjk-sans.override { static = true; })
        (noto-fonts-cjk-serif.override { static = true; })
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

    # baloo starts before kwin creates the Wayland socket, and a user unit keeps the environment
    # captured at start, so the Qt indexer extractors would abort for lack of a QPA platform.
    # The unit itself comes from the baloo package via XDG_DATA_DIRS, so a full unit file here
    # would shadow it; the drop-in extends the packaged unit instead.
    systemd.user.services."kde-baloo" = {
      overrideStrategy = "asDropin";
      environment.QT_QPA_PLATFORM = "offscreen";
    };

    security.rtkit.enable = true;

    services.pipewire = {
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
      # Write keys individually to preserve KDE-managed theme, color, and other settings.
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
