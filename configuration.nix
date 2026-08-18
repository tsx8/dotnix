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
  # dsh 的打包由 dsh-nix flake 提供，此处只负责系统级安装
  deepseekHarness = dsh-nix.packages.${pkgs.stdenv.hostPlatform.system}.deepseek-harness;

  rimeFrostData = pkgs.runCommand "rime-frost-data" { } ''
    mkdir -p "$out/share/rime-data"
    cp -r ${rimeFrostSource}/. "$out/share/rime-data/"
  '';

  # 对齐 macOS 简体拼音习惯：翻页键、标点、Shift/CapsLock 大写直上屏、切换时上屏拼音原码
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
          # 托盘右键菜单不再暴露运行时配置入口（方案切换、开关选项、部署、同步）
          sed -i \
            -e '/imAction_->setMenu/d' \
            -e '/registerAction("fcitx-rime-separator"/,/);/d' \
            -e '/registerAction("fcitx-rime-deploy"/,/);/d' \
            -e '/registerAction("fcitx-rime-sync"/,/);/d' \
            -e '/updateSchemaMenu();/d' \
            src/rimeengine.cpp
          # 输入法与插件标记为不可配置，菜单中不再出现"配置"入口
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
          # macOS Command:
          # physical Alt beside Space becomes the Cmd layer.
          leftalt = "layer(meta_mac)";
          rightalt = "layer(meta_mac)";

          # macOS Option:
          # move Alt to the physical Meta/Win positions.
          leftmeta = "alt";
          rightmeta = "rightalt";

          # Existing behavior:
          # tap CapsLock -> Ctrl+Space -> switch IME
          # hold CapsLock -> CapsLock
          capslock = "overload(capslock, C-space)";
        };

        # Based on keyd v2.6.0 examples/macos.conf.
        #
        # ":C" makes unspecified Cmd combinations behave like Ctrl.
        "meta_mac:C" = {
          # macOS Cmd+Space -> Spotlight-like launcher.
          # Plasma's KRunner uses Alt+Space.
          space = "A-space";

          # Keep upstream keyd clipboard mappings.
          #
          # Qt/KDE recognizes:
          # Ctrl+Insert  -> Copy
          # Shift+Insert -> Paste
          # Shift+Delete -> Cut
          c = "C-insert";
          v = "S-insert";
          x = "S-delete";

          # macOS Cmd+Left/Right -> beginning/end of line.
          left = "home";
          right = "end";

          # macOS Cmd+Tab -> KWin Task Switcher.
          #
          # swapm keeps Alt held while Cmd remains physically held,
          # so repeated Tab presses continue cycling.
          tab = "swapm(app_switch_state, A-tab)";

          # macOS Cmd+` -> next window of current application.
          #
          # KWin provides Alt+` for this action.
          grave = "A-grave";
        };

        # Active after Cmd+Tab until Cmd is released.
        "app_switch_state:A" = {
          # Forward through applications/windows.
          tab = "A-tab";
          right = "A-tab";

          # Backward through applications/windows.
          grave = "A-S-tab";
          left = "A-S-tab";
        };

        # Preserve the existing CapsLock hold layer.
        capslock = {
          capslock = "capslock";
        };
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

    sharedModules = [ dsh-nix.homeModules.default ];

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

        # fcitx5 默认用 Shift_L 临时切换上一个输入法（AltTrigger），清空禁用
        "Hotkey/AltTriggerKeys" = {
          "0" = "";
        };
      };

      settings.addons = {
        # macOS 拼音习惯：CapsLock(→Ctrl+Space) 切走时上屏原始拼音编码，默认上屏转换后的中文
        rime.globalSection.SwitchInputMethodBehavior = "Commit raw input";
      };
    };
  };

  # rime 部署器按文件时间戳判断是否重编译，而 nix store 文件时间戳固定为 epoch，
  # 内容变化不会触发重编译；每次激活时清掉编译缓存并以用户身份全量部署。
  system.activationScripts.rimeDeploy = ''
    if getent passwd tsxb >/dev/null; then
      echo "deploying rime data ..."
      rm -rf /home/tsxb/.local/share/fcitx5/rime/build \
        /home/tsxb/.local/share/fcitx5/rime/installation.yaml
      runuser -u tsxb -- env HOME=/home/tsxb \
        ${pkgs.librime}/bin/rime_deployer --build \
        /home/tsxb/.local/share/fcitx5/rime \
        ${fcitx5RimeFrost}/share/rime-data
      echo "rime data deployed"
    fi
  '';

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
