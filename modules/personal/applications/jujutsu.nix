{
  dotnix.modules.nixos = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.jujutsu ];
  };

  dotnix.modules.home = { config, ... }: {
    programs.jujutsu = {
      enable = true;
      package = null;

      settings = {
        user = {
          inherit (config.programs.git.settings.user) name email;
        };

        # 避免状态检查将临时文件写入版本历史。
        snapshot.auto-track = "none()";
      };
    };
  };
}
