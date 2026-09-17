{ config, inputs, ... }:

let
  userName = config.dotnix.host.userName;
in
{
  dotnix.modules.nixos = { config, pkgs, ... }: {
    imports = [ inputs.sops-nix.nixosModules.sops ];

    # nixpkgs 移除了 EOL 的 buildGo125Module，sops-nix 上游仍硬编码引用它构建
    # sops-install-secrets；以当前 builder 过渡，上游迁移后删除此别名。
    nixpkgs.overlays = [
      (_: prev: { buildGo125Module = prev.buildGoModule; })
    ];

    sops = {
      defaultSopsFile = ./secrets.yaml;
      age = {
        keyFile = "/var/lib/sops-nix/key.txt";
        generateKey = false;
      };
      secrets.user-passwd-hash.neededForUsers = true;
    };

    # GitHub API 匿名限额 60/h，flake 输入解析极易耗尽后整批输入沿用缓存版本。
    # 令牌渲染为用户级 nix.conf 供所有以本机用户身份运行的 nix 命令使用；
    # 原始密钥仅 root 可读，用户可读的只有渲染产物。
    sops.secrets.gh-auth-token = { };
    sops.templates."nix.conf" = {
      content = ''
        access-tokens = github.com=${config.sops.placeholder.gh-auth-token}
      '';
      owner = userName;
    };

    users.groups.sops = { };
    users.users.${userName} = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "sops"
      ];
      hashedPasswordFile = config.sops.secrets.user-passwd-hash.path;
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/sops-nix 0750 root sops -"
      "z /var/lib/sops-nix/key.txt 0440 root sops -"
    ];
    environment.systemPackages = [ pkgs.sops ];
  };

  dotnix.modules.home = { config, ... }: {
    home.file.".config/sops/age/keys.txt".source =
      config.lib.file.mkOutOfStoreSymlink "/var/lib/sops-nix/key.txt";
    # 指向 sops-nix 渲染产物；符号链接不入 store，密钥不落盘于明文配置。
    home.file.".config/nix/nix.conf".source =
      config.lib.file.mkOutOfStoreSymlink "/run/secrets/rendered/nix.conf";
  };

  perSystem = { pkgs, ... }: {
    packages = {
      inherit (pkgs) age sops;
    };
  };
}
