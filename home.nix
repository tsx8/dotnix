{
  config,
  lib,
  osConfig,
  ...
}:

{
  home.stateVersion = "26.05";

  # Home Manager only manages user configuration.
  # Applications belong to NixOS; project tools belong to project devShells.
  home.packages = lib.mkForce [
    config.home.sessionVariablesPackage
  ];

  home.file.".dsh/.credentials.yaml".source =
    config.lib.file.mkOutOfStoreSymlink
      osConfig.sops.templates."dsh-credentials.yaml".path;

  home.file.".gitconfig".text = ''
    [user]
      name = tsx8
      email = tangsongxiaoba@163.com
  '';

  home.file.".config/sops/age/keys.txt".source =
    config.lib.file.mkOutOfStoreSymlink "/var/lib/sops-nix/key.txt";

  xdg.configFile."fish/conf.d/editor.fish".text = ''
    if not set -q EDITOR
      set -gx EDITOR nvim
    end

    if not set -q VISUAL
      set -gx VISUAL nvim
    end
  '';

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
    };
  };
}
