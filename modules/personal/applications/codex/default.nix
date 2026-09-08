{ inputs, ... }: {
  dotnix.modules.nixos = { pkgs, ... }: {
    # 固定模型目录以覆盖长上下文上限；该快照需手动同步上游元数据。
    environment.etc."codex/models.json".source = ./models.json;
    environment.etc."codex/bash-env".text =
      builtins.replaceStrings [ "@direnv@" "@jq@" ] [ "${pkgs.direnv}/bin/direnv" "${pkgs.jq}/bin/jq" ]
        (builtins.readFile ./bash-env.sh);

    environment.etc."codex/config.toml".text = ''
      model_provider = "openai"
      model = "gpt-6-astra"
      model_catalog_json = "/etc/codex/models.json"
      model_reasoning_effort = "medium"
      approval_policy = "never"
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
      BASH_ENV = "/etc/codex/bash-env"

      [agents]
      default_subagent_model = "gpt-6-astra"
      default_subagent_reasoning_effort = "low"

      [features]
      context_management.experimental_mode = true
    '';

    environment.systemPackages = [
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.chatgpt
      pkgs.bubblewrap
    ];
  };
  dotnix.modules.home = {
    home.file.".codex/AGENTS.md".source = ./AGENTS-md.txt;
  };
}
