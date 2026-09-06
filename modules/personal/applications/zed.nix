{
  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      zed-editor
      nixd
    ];
  };
  dotnix.modules.home = {
    programs.zed-editor = {
      enable = true;
      package = null;

      mutableUserSettings = false;

      extensions = [
        "nix"
      ];

      userSettings = {
        agent.button = false;
        autosave.after_delay.milliseconds = 0;

        auto_update = false;
        base_keymap = "VSCode";

        edit_predictions.provider = "none";

        languages.Nix.language_servers = [
          "nixd"
          "!nil"
        ];

        lsp.gopls.binary.path_lookup = true;

        session.trust_all_worktrees = true;

        terminal = {
          env = {
            EDITOR = "zeditor --wait";
            VISUAL = "zeditor --wait";
          };
        };
      };
    };
  };
}
