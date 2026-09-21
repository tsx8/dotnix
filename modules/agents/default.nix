{ inputs, ... }:
{
  dotnix.modules.nixos = { pkgs, ... }: {
    environment.etc."direnv/bash-env".text =
      builtins.replaceStrings [ "@direnv@" "@jq@" ] [ "${pkgs.direnv}/bin/direnv" "${pkgs.jq}/bin/jq" ]
        (builtins.readFile ./bash-env.sh);

    # direnv 只在 ConfDir 存在配置文件时才读取 DIRENV_LOG_FORMAT 环境变量，
    # 空文件即满足；toml 无法表达关闭日志，由 bash-env.sh 以空值变量实现。
    environment.etc."direnv/config.toml".text = "";
  };

  # 代理技能装配点：本地 skills/ 树与外部 flake input 统一装到
  # ~/.agents/skills/（Agent Skills 标准位置），不绑定具体 harness。
  dotnix.modules.home = {
    home.file.".agents/skills/helium-use".source = ../../skills/helium-use;
    home.file.".agents/skills/obelisk".source = "${inputs.obelisk-skill}/skills/obelisk";
  };
}
