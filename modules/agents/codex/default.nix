{ config, inputs, ... }: {
  dotnix.modules.nixos = { pkgs, ... }: {
    # 固定模型目录以覆盖长上下文上限。
    environment.etc."codex/models.json".source = ./models.json;

    environment.etc."codex/config.toml".text = ''
      model_provider = "openai"
      model = "gpt-6-astra"
      model_catalog_json = "/etc/codex/models.json"
      model_reasoning_effort = "low"
      approval_policy = "on-request"
      approvals_reviewer = "user"
      sandbox_mode = "danger-full-access"
      # 非登录 Bash 避免恢复旧快照，环境由 BASH_ENV 按命令目录加载。
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

      # git marketplace 改由 flake input 锁定的本地源提供，版本随 repo update 更新；
      # 插件缓存按 plugin.json 版本分目录，上游需正常 bump 版本号才会触发重载。
      [marketplaces.kami]
      source_type = "local"
      source = "${inputs.kami}"

      [marketplaces.waza]
      source_type = "local"
      source = "${inputs.waza}"

      [plugins."kami@kami"]
      enabled = true

      [plugins."waza@waza"]
      enabled = true
    '';

    environment.systemPackages = [
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.chatgpt
      pkgs.bubblewrap
    ];
  };
  dotnix.modules.home =
    { lib, pkgs, ... }:
    let
      mcpPackages = config.flake.packages.${pkgs.stdenv.hostPlatform.system};
    in
    {
      # 源文件保持 .txt 后缀，避免被按目录级 AGENTS.md 扫描的工具误拾取。
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
                # auto 仍会询问危险工具；认证由 polkit 逐次执行。
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
