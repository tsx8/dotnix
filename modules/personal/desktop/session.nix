{
  dotnix.modules.nixos = { pkgs, ... }: {
    # Old Electron needs static fonts; a global override would invalidate cached KDE dependencies.
    fonts.packages = with pkgs; [
      (noto-fonts-cjk-sans.override { static = true; })
      (noto-fonts-cjk-serif.override { static = true; })
    ];

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

  # Home Manager leaves omitted KConfig keys on disk; null restores Plasma's defaults.
  dotnix.modules.home.qt.kde.settings.kdeglobals = {
    General = {
      font = null;
      menuFont = null;
      toolBarFont = null;
      taskbarFont = null;
      smallestReadableFont = null;
    };
    WM.activeFont = null;
  };
}
