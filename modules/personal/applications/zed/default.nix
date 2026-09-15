{
  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = [
      pkgs.zed-editor
      pkgs.nixd
    ];
  };
  dotnix.modules.home = { pkgs, ... }: {
    xdg.configFile."zed/keymap.json".source =
      pkgs.runCommand "zed-vscode-macos-keymap.json"
        { nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.json5 ])) ]; }
        ''
          python3 ${./keymap.py} \
            ${pkgs.zed-editor.src}/assets/keymaps/default-macos.json \
            ${pkgs.zed-editor.src}/assets/keymaps/macos/vscode.json \
            ${pkgs.zed-editor.src}/assets/keymaps/specific-overrides-macos.json > $out
        '';
    programs.zed-editor = {
      enable = true;
      package = null;

      mutableUserSettings = false;
      mutableUserKeymaps = false;

      extensions = [
        "nix"
      ];

      userSettings = {
        agent.button = false;
        autosave.after_delay.milliseconds = 0;

        auto_update = false;
        # Linux 的 VSCode 预设使用 Linux 修饰键；macOS 键表在上方生成并适配 Toshy。
        base_keymap = "None";

        edit_predictions.provider = "none";

        git_panel = {
          tree_view = true;
          group_by = "staging";
        };

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
