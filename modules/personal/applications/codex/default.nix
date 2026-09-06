{ inputs, ... }: {
  dotnix.modules.nixos = { pkgs, ... }: {
    # 固定模型目录以覆盖长上下文上限；该快照需手动同步上游元数据。
    environment.etc."codex/models.json".source = ./models.json;

    environment.etc."codex/config.toml".text = ''
      model_provider = "openai"
      model = "gpt-6-astra"
      model_catalog_json = "/etc/codex/models.json"
      model_reasoning_effort = "medium"
      approval_policy = "on-request"
      sandbox_mode = "workspace-write"
      web_search = "live"
      model_verbosity = "low"
      model_reasoning_summary = "detailed"
      [desktop]
      localeOverride = "zh-CN"
      preventSleepWhileRunning = true
      composerEnterBehavior = "cmdAlways"
      followUpQueueMode = "queue"

      [sandbox_workspace_write]
      network_access = false
      # 仅匹配 NIX_CACHE_HOME/XDG_CACHE_HOME 均未设置时的默认值；
      # 重定向 Nix cache 后需同步更新此路径并重启 Codex。
      writable_roots = ["~/.cache/nix"]

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
