{ config, ... }:
let
  userName = config.dotnix.host.userName;
in
{
  dotnix.modules.nixos =
    { lib, pkgs, ... }:
    let
      # ZeroTier online toggle: start/stop the single service passwordlessly via systemd D-Bus + polkit.
      # Not sudo/pkexec/zerotier-cli stop — the upstream unit has Restart=always, so a CLI self-exit gets restarted;
      # a failed notification must not be misread as a failed systemd operation
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
      # On-demand virtual network for BG3 online play: the systemd service does not start at boot; the KDE
      # launchers start/stop it passwordlessly. Network membership and moon runtime state live in
      # /var/lib/zerotier-one; moons/ is a backup of the moon file
      environment.systemPackages = [
        zerotier-start
        zerotier-stop
      ];

      services.zerotierone = {
        enable = true;
        joinNetworks = [ "a0cbf4b62a7da602" ];
      };

      systemd.services.zerotierone.wantedBy = lib.mkForce [ ];

      # Allow only the local active desktop user to start/stop this unit without a password; on no match,
      # return nothing and fall back to the existing policies, leaving the MCP privilege rules untouched
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
