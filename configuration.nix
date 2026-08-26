{
  config,
  lib,
  pkgs,
  dsh-nix,
  rimeFrostSource,
  ...
}:

let
  fcitx5Rime = pkgs.fcitx5-rime.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      # 保留声明式配置入口，但不在托盘菜单暴露 Rime 运行时操作。
      sed -i \
        -e '/imAction_->setMenu/d' \
        -e '/registerAction("fcitx-rime-separator"/,/);/d' \
        -e '/registerAction("fcitx-rime-deploy"/,/);/d' \
        -e '/registerAction("fcitx-rime-sync"/,/);/d' \
        -e '/updateSchemaMenu();/d' \
        src/rimeengine.cpp

      substituteInPlace src/rime.conf.in \
        --replace-fail 'Configurable=True' 'Configurable=False'
    '';
  });
in
{
  imports = [ ./network.nix ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking = {
    hostName = "maco";
  };

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

  hardware.facter = {
    reportPath = ./facter.json;
    detected.dhcp.enable = false;
  };

  services.btrfs.autoScrub.enable = true;

  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowHibernation = false;
    AllowHybridSleep = false;
    AllowSuspendThenHibernate = false;
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
      wifi-hotspot-password = { };
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
          version: 1
          refs:
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
  programs.deepseek-harness.enable = true;
  programs.direnv.enable = true;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = false;

    extraSpecialArgs = {
      inherit rimeFrostSource;
    };

    sharedModules = [ dsh-nix.homeModules.default ];

    users.tsxb = import ./home.nix;
  };

  users.groups.sops = { };

  systemd.tmpfiles.rules = [
    "d /var/lib/sops-nix 0750 root sops -"
    "z /var/lib/sops-nix/key.txt 0440 root sops -"
  ];

  users.users.tsxb = {
    isNormalUser = true;

    extraGroups = [
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
        fcitx5Rime
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

    # hostapd/802.11 排障：查看 wiphy 能力、信道与工作带宽
    iw

    nixd
  ];

  zramSwap.enable = true;

  system.stateVersion = "26.05";
}
