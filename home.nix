{
  config,
  lib,
  osConfig,
  ...
}:

{
  home.stateVersion = "26.05";

  programs.deepseek-harness = {
    enable = true;
    # 应用由 NixOS 系统级安装，Home Manager 只管理用户级配置
    package = null;

    agentsFile.source = ./dsh/AGENTS.md;
  };

  # Home Manager only manages user configuration.
  # Applications belong to NixOS; project tools belong to project devShells.
  home.packages = lib.mkForce [
    config.home.sessionVariablesPackage
  ];

  home.file.".dsh/.credentials.yaml".source =
    config.lib.file.mkOutOfStoreSymlink
      osConfig.sops.templates."dsh-credentials.yaml".path;

  home.file.".config/sops/age/keys.txt".source =
    config.lib.file.mkOutOfStoreSymlink "/var/lib/sops-nix/key.txt";

  programs.git = {
    enable = true;
    package = null;

    settings = {
      user = {
        name = "tsx8";
        email = "tangsongxiaoba@163.com";
      };

      credential."https://github.com".helper = "!gh auth git-credential";
    };
  };

  programs.zed-editor = {
    enable = true;
    package = null;

    userSettings = {
      terminal = {
        env = {
          EDITOR = "zeditor --wait";
          VISUAL = "zeditor --wait";
        };
      };

      languages = {
        Nix = {
          language_servers = [
            "nixd"
            "!nil"
          ];
        };
      };
    };
  };
}
