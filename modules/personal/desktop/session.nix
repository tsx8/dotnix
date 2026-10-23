{
  dotnix.modules.nixos = { pkgs, lib, ... }: {
    # The defaults are VF variable fonts; switch to the static builds for compatibility with apps that
    # cannot use variable fonts (e.g. QQ Music and Tencent Meeting, packaged with Electron 8)
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
            # Keep a store reference to the original font so the system closure protects the build input from GC.
            install -d "$out/share/fonts/truetype"
            ln -s "$src" "$out/share/fonts/truetype/PingFang.ttc"
          ''
        )
        # Neovim's UI icons are Nerd Font glyphs; the symbols-only face supplies them without replacing the terminal text font.
        nerd-fonts.symbols-only
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
