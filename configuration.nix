{
  config,
  lib,
  pkgs,
  daeuniverse,
  rimeFrostSource,
  ...
}:

let
  dsh = pkgs.writeShellApplication {
    name = "dsh";

    runtimeInputs = [
      pkgs.nodejs_24
      pkgs.bubblewrap
    ];

    text = ''
      exec npx --yes @deepseek-ai/dsh@0.1.0-rc.6 "$@"
    '';
  };

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

  fonts.packages = with pkgs; [
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
  ];

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
    };
  };

  environment.etc."xdg/kwinrc".text = ''
    [Wayland]
    InputMethod=${config.i18n.inputMethod.package}/share/applications/fcitx5-wayland-launcher.desktop
  '';

  # Useful immediately after first boot.
  programs.firefox.enable = true;

  environment.systemPackages = with pkgs; [
    git
    just
    sops

    curl
    wget
    jq
    fd
    ripgrep

    neovim
    zed-editor.fhs

    dsh
  ];

  zramSwap.enable = true;

  system.stateVersion = "26.05";
}
