{ inputs, ... }: {
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

      # git marketplace 改由 flake input 锁定的本地源提供，版本随 repo update 晋进；
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
  dotnix.modules.home = {
    home.file.".codex/AGENTS.md".source = ./AGENTS-md.txt;
    home.file.".codex/skills/obelisk".source = "${inputs.obelisk-skill}/skills/obelisk";
  };
}
