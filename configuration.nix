{
  config,
  lib,
  pkgs,
  daeuniverse,
  rimeFrostSource,
  ...
}:

let
  deepseekHarness = pkgs.callPackage ./packages/deepseek-harness/package.nix { };

  rimeFrostData = pkgs.runCommand "rime-frost-data" { } ''
    mkdir -p "$out/share/rime-data"
    cp -r ${rimeFrostSource}/. "$out/share/rime-data/"
  '';

  fcitx5RimeFrost = pkgs.fcitx5-rime.override {
    rimeDataPkgs = [ rimeFrostData ];
  };
in
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking = {
    hostName = "maco";
    networkmanager.enable = true;
  };

  services.buaa-login = {
    enable = true;
    credentialsFile = config.sops.secrets.buaa-login.path;
  };

  services.dae = {
    enable = true;

    package = daeuniverse.packages.${pkgs.stdenv.hostPlatform.system}.dae-unstable;

    configFile = config.sops.templates."dae.dae".path;
  };

  systemd.services.buaa-login.unitConfig.OnSuccess = [
    "dae.service"
  ];

  systemd.services.dae.wantedBy = lib.mkForce [ ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  hardware.facter = {
    reportPath = ./facter.json;
    detected.dhcp.enable = false;
  };

  time.timeZone = "Asia/Shanghai";

  i18n.defaultLocale = "en_US.UTF-8";

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

  # Secrets
  sops = {
    defaultSopsFile = ./secrets.yaml;

    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = false;
    };

    secrets = {
      deepseek-api-key = { };
      dae-nodes = { };
      buaa-login = { };
      user-passwd-hash = {
        neededForUsers = true;
      };
    };

    templates = {
      "dae.dae".content = builtins.readFile ./dae.dae + "\n" + config.sops.placeholder.dae-nodes;

      "dsh-credentials.yaml" = {
        owner = config.users.users.tsxb.name;
        mode = "0400";

        content = ''
          DEEPSEEK_API_KEY: ${config.sops.placeholder.deepseek-api-key}
        '';
      };
    };
  };

  # Desktop
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Keyboard: macOS-like layout, remapped at evdev level by keyd (applies to X11/Wayland/TTY)
  services.keyd = {
    enable = true;

    keyboards.default = {
      ids = [ "*" ];

      settings = {
        main = {
          leftalt = "leftmeta"; # Cmd lands on the thumb key left of space
          leftmeta = "leftalt"; # Option lands where Win used to be
          rightalt = "rightmeta";
          rightmeta = "rightalt";

          # macOS: tap CapsLock switches Chinese/English input, hold enables Caps Lock
          capslock = "overload(capslock, C-space)";
        };

        capslock.capslock = "capslock";
      };
    };
  };

  # Audio
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Shell
  programs.fish.enable = true;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = false;

    users.tsxb = import ./home.nix;
  };

  users.groups.sops = { };

  systemd.tmpfiles.rules = [
    "d /var/lib/sops-nix 0750 root sops -"
    "z /var/lib/sops-nix/key.txt 0440 root sops -"
  ];

  # User
  users.users.tsxb = {
    isNormalUser = true;

    extraGroups = [
      "networkmanager"
      "wheel"
      "sops"
    ];

    shell = pkgs.fish;

    hashedPasswordFile = config.sops.secrets.user-passwd-hash.path;
  };

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";

    fcitx5 = {
      waylandFrontend = true;

      addons = [
        fcitx5RimeFrost
      ];

      settings.inputMethod = {
        "Groups/0" = {
          Name = "Default";
          "Default Layout" = "us";
          DefaultIM = "rime";
        };

        "Groups/0/Items/0" = {
          Name = "keyboard-us";
          Layout = "";
        };

        "Groups/0/Items/1" = {
          Name = "rime";
          Layout = "";
        };

        GroupOrder = {
          "0" = "Default";
        };
      };

      settings.globalOptions = {
        "Hotkey" = {
          # keyd translates a CapsLock tap into this chord, toggling keyboard-us <-> rime
          "EnumerateWithTriggerKeys" = "False";
        };

        # fcitx5 key lists use indexed sub-sections; a scalar TriggerKeys value is silently ignored
        "Hotkey/TriggerKeys" = {
          "0" = "Control+space";
        };
      };
    };
  };

  environment.etc."xdg/kwinrc".text = ''
    [Wayland]
    InputMethod=${config.i18n.inputMethod.package}/share/applications/fcitx5-wayland-launcher.desktop
  '';

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  programs.helium = {
    enable = true;
    flags = [
      "--ozone-platform-hint=auto"
      "--enable-wayland-ime=true"
    ];
    policies.ExtensionInstallForcelist = [
      "bdiifdefkgmcblbcghdlonllpjhhjgof" # KISS Translator
      "onnepejgdiojhiflfoemillegpgpabdm" # V2EX Polish
      "dhdgffkkebhmkfjojejmpbldmpobfkfo" # Tampermonkey
    ];
  };

  environment.systemPackages = with pkgs; [
    git
    just
    sops

    curl
    wget
    jq
    fd
    ripgrep

    gh
    neovim
    zed-editor

    nixd

    deepseekHarness
  ];

  zramSwap.enable = true;

  system.stateVersion = "26.05";
}
