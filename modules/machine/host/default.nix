{
  dotnix.modules.nixos = { pkgs, ... }: {
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    nix.channel.enable = false;

    boot.loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 10;
        editor = false;
      };
      efi.canTouchEfiVariables = true;
    };

    # system.nixos.label = "nixos"; donot enable this, use NIXOS_LABEL instead

    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    boot.kernelPackages = pkgs.linuxPackages_latest;
    hardware.facter.reportPath = ./facter.json;

    systemd.sleep.settings.Sleep = {
      AllowSuspend = false;
      AllowHibernation = false;
      AllowHybridSleep = false;
      AllowSuspendThenHibernate = false;
    };

    time.timeZone = "Asia/Shanghai";
    i18n.defaultLocale = "en_US.UTF-8";
    programs.nix-ld.enable = true;
    zramSwap.enable = true;
    system.stateVersion = "26.05";
  };

  perSystem = { pkgs, ... }: {
    packages.nixos-facter = pkgs.nixos-facter;
  };
}
