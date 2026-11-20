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

    # Baloo can start before the Wayland socket; extend its packaged unit rather than shadow it.
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
