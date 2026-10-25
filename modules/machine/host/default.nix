{
  dotnix.modules.nixos = { pkgs, ... }: {
    nixpkgs.config.allowUnfree = true;

    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    nix.channel.enable = false;

    # One derivation built with NIX_BUILD_CORES=24 fans out to 24 g++ at ~0.9 GiB each,
    # which let a single build reach 26 GiB of RAM on this 29.7 GiB machine.
    nix.settings.cores = 8;

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
