{ config, ... }:
let
  userName = config.dotnix.host.userName;
in
{
  dotnix.modules.nixos =
    { lib, pkgs, ... }:
    let
      # ZeroTier 联机开关：经 systemd D-Bus + polkit 免密启停单个服务。
      # 不用 sudo/pkexec/zerotier-cli stop——上游单元 Restart=always，CLI 自行退出会被拉回；
      # 通知失败不得误判为 systemd 操作失败
      zerotier-control = pkgs.writeShellApplication {
        name = "zerotier-control";
        runtimeInputs = [
          pkgs.systemd
          pkgs.libnotify
        ];
        text = ''
          case "''${1:-}" in
            start)
              if systemctl is-active --quiet zerotierone.service; then
                notify-send "ZeroTier" "服务已在运行" || true
              elif systemctl start zerotierone.service; then
                notify-send "ZeroTier" "服务已开启，网络就绪需数秒" || true
              else
                notify-send "ZeroTier" "服务启动失败" || true
                exit 1
              fi
              ;;
            stop)
              if ! systemctl is-active --quiet zerotierone.service; then
                notify-send "ZeroTier" "服务未在运行" || true
              elif systemctl stop zerotierone.service; then
                notify-send "ZeroTier" "服务已关闭" || true
              else
                notify-send "ZeroTier" "服务停止失败" || true
                exit 1
              fi
              ;;
            *)
              echo "usage: zerotier-control {start|stop}" >&2
              exit 2
              ;;
          esac
        '';
      };

      zerotier-start = pkgs.makeDesktopItem {
        name = "zerotier-start";
        desktopName = "开启 ZeroTier";
        exec = "${zerotier-control}/bin/zerotier-control start";
        icon = "network-vpn";
        categories = [ "Network" ];
        terminal = false;
        startupNotify = false;
      };

      zerotier-stop = pkgs.makeDesktopItem {
        name = "zerotier-stop";
        desktopName = "关闭 ZeroTier";
        exec = "${zerotier-control}/bin/zerotier-control stop";
        icon = "network-vpn";
        categories = [ "Network" ];
        terminal = false;
        startupNotify = false;
      };
    in
    {
      # 为 BG3 联机服务的按需虚拟网：systemd 服务不开机自启，KDE 启动器免密启停；
      # 入网与 moon 运行态在 /var/lib/zerotier-one，moons/ 为 moon 文件备份
      environment.systemPackages = [
        zerotier-start
        zerotier-stop
      ];

      services.zerotierone = {
        enable = true;
        joinNetworks = [ "a0cbf4b62a7da602" ];
      };

      systemd.services.zerotierone.wantedBy = lib.mkForce [ ];

      # 仅免密允许本机活动桌面用户 start/stop 该单元；不匹配时不返回结果，
      # 交回原有策略，不影响既有 MCP 提权规则
      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id !== "org.freedesktop.systemd1.manage-units") return;
          if (action.lookup("unit") !== "zerotierone.service") return;
          const verb = action.lookup("verb");
          if (verb !== "start" && verb !== "stop") return;
          if (subject.user !== ${builtins.toJSON userName} || !subject.local || !subject.active) return;
          return polkit.Result.YES;
        });
      '';
    };
}
