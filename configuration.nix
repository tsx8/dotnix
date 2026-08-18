{
  config,
  lib,
  pkgs,
  daeuniverse,
  dsh-nix,
  rimeFrostSource,
  ...
}:

let
  deepseekHarness = dsh-nix.packages.${pkgs.stdenv.hostPlatform.system}.deepseek-harness;

  rimeFrostData = pkgs.runCommand "rime-frost-data" { } ''
    mkdir -p "$out/share/rime-data"
    cp -r ${rimeFrostSource}/. "$out/share/rime-data/"
  '';

  rimeMacosCompat = pkgs.runCommand "rime-macos-compat" { } ''
    mkdir -p "$out/share/rime-data/lua"
    cp ${./rime/default.custom.yaml} "$out/share/rime-data/default.custom.yaml"
    cp ${./rime/rime_frost.custom.yaml} "$out/share/rime-data/rime_frost.custom.yaml"
    cp ${./rime/lua/direct_uppercase.lua} "$out/share/rime-data/lua/direct_uppercase.lua"
  '';

  fcitx5RimeFrost =
    (pkgs.fcitx5-rime.override {
      rimeDataPkgs = [
        rimeFrostData
        rimeMacosCompat
      ];
    }).overrideAttrs
      (old: {
        postPatch = (old.postPatch or "") + ''
          # 托盘菜单不暴露运行时配置入口
          sed -i \
            -e '/imAction_->setMenu/d' \
            -e '/registerAction("fcitx-rime-separator"/,/);/d' \
            -e '/registerAction("fcitx-rime-deploy"/,/);/d' \
            -e '/registerAction("fcitx-rime-sync"/,/);/d' \
            -e '/updateSchemaMenu();/d' \
            src/rimeengine.cpp
          substituteInPlace src/rime.conf.in --replace 'Configurable=True' 'Configurable=False'
          substituteInPlace src/rime-addon.conf.in.in --replace 'Configurable=True' 'Configurable=False'
        '';
      });

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

  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # macOS 键位：keyd 在 evdev 层重映射（X11/Wayland/TTY 均生效）
  services.keyd = {
    enable = true;

    keyboards.default = {
      ids = [ "*" ];

      settings = {
        main = {
          leftalt = "layer(meta_mac)";
          rightalt = "layer(meta_mac)";
          leftmeta = "alt";
          rightmeta = "rightalt";

          capslock = "overload(capslock, C-space)";
        };

        # 基于 keyd v2.6.0 examples/macos.conf。
        # ":C" 让未显式定义的 Cmd 组合按 Ctrl 处理。
        "meta_mac:C" = {
          # Plasma 的 KRunner 用 Alt+Space
          space = "A-space";

          # Qt/KDE 仅识别 Insert/Delete 形式的剪贴板快捷键
          c = "C-insert";
          v = "S-insert";
          x = "S-delete";

          left = "home";
          right = "end";

          # swapm：Cmd 按住期间维持 Alt，Tab 可连续切换
          tab = "swapm(app_switch_state, A-tab)";

          # KWin 用 Alt+` 切换当前应用窗口
          grave = "A-grave";
        };

        "app_switch_state:A" = {
          tab = "A-tab";
          right = "A-tab";
          grave = "A-S-tab";
          left = "A-S-tab";
        };

        # overload 的 hold 动作：长按保持 CapsLock
        capslock = {
          capslock = "capslock";
        };
      };
    };
  };

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  programs.fish.enable = true;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = false;

    sharedModules = [ dsh-nix.homeModules.default ];

    users.tsxb = import ./home.nix;
  };

  users.groups.sops = { };

  systemd.tmpfiles.rules = [
    "d /var/lib/sops-nix 0750 root sops -"
    "z /var/lib/sops-nix/key.txt 0440 root sops -"
  ];

  security.sudo.extraRules = [
    {
      groups = [ "wheel" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

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
          # 点按 CapsLock 由 keyd 转为该组合键，切换 keyboard-us ↔ rime
          "EnumerateWithTriggerKeys" = "False";
        };

        # 键列表用编号子节，写成标量会被静默忽略
        "Hotkey/TriggerKeys" = {
          "0" = "Control+space";
        };

        # Shift 已用于大写直上屏，禁用 AltTrigger 的临时切换
        "Hotkey/AltTriggerKeys" = {
          "0" = "";
        };
      };

      settings.addons = {
        # 对齐 macOS：切走时上屏原始拼音（默认上屏中文）
        rime.globalSection.SwitchInputMethodBehavior = "Commit raw input";
      };
    };
  };

  environment.etc."xdg/kwinrc".text = ''
    [Wayland]
    InputMethod=${config.i18n.inputMethod.package}/share/applications/fcitx5-wayland-launcher.desktop

    [TabBox]
    ApplicationsMode=1
  '';

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  programs.nix-ld.enable = true;

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
