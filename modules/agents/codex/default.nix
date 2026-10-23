{ config, inputs, ... }: {
  dotnix.modules.nixos =
    { pkgs, ... }:
    let
      chatgpt = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.chatgpt;
      # The current build links remote-control-device-key.node against tpm2-tss; the upstream
      # fixup does not carry those libraries, so add them to the unwrapped package.
      chatgpt-unwrapped = chatgpt.unwrapped.overrideAttrs (old: {
        buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.tpm2-tss ];
      });
    in
    {
      # Pin the model catalog to override the long-context limit.
      environment.etc."codex/models.json".source = ./models.json;

      environment.etc."codex/config.toml".text = ''
        model_provider = "openai"
        model = "gpt-6-astra"
        model_catalog_json = "/etc/codex/models.json"
        model_reasoning_effort = "low"
        approval_policy = "on-request"
        approvals_reviewer = "user"
        sandbox_mode = "danger-full-access"
        # Non-login Bash avoids restoring a stale snapshot; the environment loads via BASH_ENV per command directory.
        allow_login_shell = false
        web_search = "live"
        model_verbosity = "low"
        model_reasoning_summary = "detailed"
        [desktop]
        localeOverride = "zh-CN"
        preventSleepWhileRunning = true
        composerEnterBehavior = "cmdAlways"
        followUpQueueMode = "queue"

        [shell_environment_policy.set]
        BASH_ENV = "/etc/direnv/bash-env"

      '';

      environment.systemPackages = [
        (chatgpt.override { inherit chatgpt-unwrapped; })
        pkgs.bubblewrap
      ];
    };
  dotnix.modules.home =
    { lib, pkgs, ... }:
    let
      mcpPackages = config.flake.packages.${pkgs.stdenv.hostPlatform.system};
    in
    {
      # The source file keeps its .txt suffix so tools scanning for directory-level AGENTS.md files do not pick it up.
      home.file.".codex/AGENTS.md".source = ../AGENTS-md.txt;

      programs.codex = {
        enable = true;
        package = null;
        mutableSettings = true;
        settings.mcp_servers = {
          mcp-dotnix = {
            command = "${pkgs.coreutils}/bin/env";
            args = [
              "-u"
              "PYTHONPATH"
              (lib.getExe mcpPackages.mcp-dotnix)
            ];
            enabled = true;
            required = false;
            startup_timeout_sec = 120;
            tool_timeout_sec = 600;
            enabled_tools = [
              "system_status"
              "unit_status"
              "unit_journal"
              "kernel_log"
              "boot_list"
              "disk_status"
              "network_status"
              "nixos_generations"
              "run_privileged"
            ];
            default_tools_approval_mode = "auto";
            tools = {
              system_status = {
                approval_mode = "auto";
                output_token_limit = 2500;
              };
              unit_status = {
                approval_mode = "auto";
                output_token_limit = 1800;
              };
              unit_journal = {
                approval_mode = "auto";
                output_token_limit = 4000;
              };
              kernel_log = {
                approval_mode = "auto";
                output_token_limit = 4000;
              };
              boot_list = {
                approval_mode = "auto";
                output_token_limit = 1800;
              };
              disk_status = {
                approval_mode = "auto";
                output_token_limit = 2500;
              };
              network_status = {
                approval_mode = "auto";
                output_token_limit = 2500;
              };
              nixos_generations = {
                approval_mode = "auto";
                output_token_limit = 1800;
              };
              run_privileged = {
                # auto would still prompt for dangerous tools; authentication runs through polkit per call.
                approval_mode = "approve";
                output_token_limit = 6000;
              };
            };
          };
          mcp-nixos = {
            command = "${pkgs.coreutils}/bin/env";
            args = [
              "-u"
              "PYTHONPATH"
              (lib.getExe mcpPackages.mcp-nixos)
            ];
            enabled = true;
            required = false;
            startup_timeout_sec = 120;
            tool_timeout_sec = 60;
            default_tools_approval_mode = "auto";
          };
        };
      };
    };
}
