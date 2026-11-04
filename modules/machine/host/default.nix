{
  dotnix.modules.nixos = { pkgs, ... }: {
    nixpkgs.config.allowUnfree = true;

    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    nix.channel.enable = false;

    # Two-layer resource control: build.slice owns foreground isolation (CPU weight) and the
    # total memory ceiling (MemoryHigh); cores only sets per-derivation parallelism. 16 is the
    # measured optimum under the 16G cap (plasma-workspace 465s vs 630s at 8); 24 fans past
    # the cap into reclaim slowdown.
    nix.settings.cores = 16;

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

    # A power event loses the last minutes of journal entries at the default 5 min sync
    # window, which is the evidence separating a system hang from a power cut.
    services.journald.settings.Journal.SyncIntervalSec = "1s";

    systemd.sleep.settings.Sleep = {
      AllowSuspend = false;
      AllowHibernation = false;
      AllowHybridSleep = false;
      AllowSuspendThenHibernate = false;
    };

    # Builds yield to the interactive session only under contention, and their reclaim
    # stays in this cgroup instead of pushing the whole machine into zram.
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
