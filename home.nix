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
    # 应用由 NixOS 系统级安装
    package = null;

    agentsFile.source = ./dsh/AGENTS.md;
  };

  # 仓库原则：应用不进用户环境
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
