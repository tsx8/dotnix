{
  dotnix.modules.nixos = { pkgs, lib, ... }: {
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
