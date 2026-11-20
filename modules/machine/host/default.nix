{
  dotnix.modules.nixos = { pkgs, ... }: {
    nixpkgs.config.allowUnfree = true;

    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    nix.channel.enable = false;

    # Within the 16 GiB build slice, more than 16 compiler jobs slowed builds through reclaim.
    nix.settings.cores = 16;

    nix.settings.substituters = [
      "https://mirrors.cernet.edu.cn/nix-channels/store"
      "https://cache.nixos.org/"
    ];

    boot.loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 10;
        editor = false;
      };
      efi.canTouchEfiVariables = true;
    };

    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    boot.kernelPackages = pkgs.linuxPackages_latest;
    hardware.facter.reportPath = ./facter.json;

    # Keep the last seconds of journal evidence across a sudden power cut.
    services.journald.settings.Journal.SyncIntervalSec = "1s";

    systemd.sleep.settings.Sleep = {
      AllowSuspend = false;
      AllowHibernation = false;
      AllowHybridSleep = false;
      AllowSuspendThenHibernate = false;
    };

    # Confine build reclaim to this slice rather than pushing the desktop into zram.
    systemd.slices.build = {
      description = "Bulk Nix builds that must not starve the interactive session";
      wantedBy = [ "slices.target" ];
      sliceConfig = {
        CPUWeight = 50;
        MemoryHigh = "16G";
      };
    };
    systemd.services.nix-daemon.serviceConfig.Slice = "build.slice";

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
