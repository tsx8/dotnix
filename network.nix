{
  config,
  lib,
  pkgs,
  daeuniverse,
  ...
}:

{
  networking = {
    useNetworkd = true;
    useDHCP = false;
    enableIPv6 = false;
    firewall.enable = false;
  };

  # WAN DNS：networkd 在 eno1 DHCP 获取 → resolved 保管 → dnsmasq 转发。
  services.resolved.enable = true;

  services.dnsmasq = {
    enable = true;

    # 本机走 resolved；dnsmasq 只服务 LAN 客户端，避免劫持本机 DNS。
    resolveLocalQueries = false;

    settings = {
      interface = "br-lan";
      # bind-dynamic 容忍网络接口晚于 dnsmasq 出现（避免与 networkd 建 br-lan 竞态）。
      bind-dynamic = true;
      no-resolv = true;

      # 上抛私域解析，脱离校园网误配的私有上游。
      domain-needed = true;

      # 转发到 resolved 的 stub，不硬编码校园网 DNS。
      server = [ "127.0.0.53" ];

      dhcp-range = [ "192.168.77.100,192.168.77.254,12h" ];
      dhcp-option = [
        "option:router,192.168.77.1"
        "option:dns-server,192.168.77.1"
      ];
    };
  };

  # br-lan：路由器 LAN 侧二层桥。
  systemd.network.netdevs."br-lan" = {
    netdevConfig = {
      Name = "br-lan";
      Kind = "bridge";
    };
  };

  # WAN：eno1，DHCPv4（校园网）。
  systemd.network.networks."30-eno1" = {
    matchConfig.Name = "eno1";
    networkConfig = {
      DHCP = "ipv4";
      LinkLocalAddressing = "ipv4";
    };
  };

  # br-lan 网关 + NAT；NAT 用 networkd 原生 IPMasquerade（networking.nat 在 firewall off 时不装 masquerade 规则）。
  systemd.network.networks."30-br-lan" = {
    matchConfig.Name = "br-lan";
    address = [ "192.168.77.1/24" ];
    networkConfig = {
      IPMasquerade = "ipv4";
      IPv4Forwarding = true;
      LinkLocalAddressing = "ipv4";
    };
  };

  systemd.network.networks."40-enp196s0" = {
    matchConfig.Name = "enp196s0";
    networkConfig.Bridge = "br-lan";
  };

  # wait-online 只等 WAN (eno1)。br-lan 桥在无活动端口时无 carrier，永不到 online，会卡住 wait-online。
  systemd.network.wait-online.ignoredInterfaces = [
    "enp196s0"
    "br-lan"
  ];

  # hostapd 接管 wlp194s0（AP + 桥接进 br-lan），故不单独给它配 networkd。
  services.hostapd = {
    enable = true;

    radios.wlp194s0 = {
      band = "5g";
      channel = 149; # CN 非 DFS（5725–5825），MT7925 上 80MHz 可用。
      countryCode = "CN";

      settings = {
        bridge = "br-lan";
        # 80MHz center segment（ch149 → 155）：EHT 启用时 hostapd 的 DFS 路径取
        # eht_oper_centr_freq_seg0_idx，不设则恒 0 → dfs_get_start_chan_idx 算出
        # -6 报 "DFS chan_idx seems wrong" 初始化失败（与内核版本无关）。
        vht_oper_centr_freq_seg0_idx = 155;
        he_oper_centr_freq_seg0_idx = 155;
        eht_oper_centr_freq_seg0_idx = 155;
      };

      # [HT40+] 让 hostapd 的 secondary_channel=1（config_file.c 唯一设置入口），
      # 否则固定信道下恒 0，80/160MHz 报 "no second channel offset"。不要用 settings.ht_capab 覆盖。
      wifi4 = {
        enable = true;
        capabilities = [
          "HT40+"
          "SHORT-GI-20"
          "SHORT-GI-40"
        ];
      };

      wifi5 = {
        enable = true;
        operatingChannelWidth = "80";
      };
      wifi6 = {
        enable = true;
        operatingChannelWidth = "80";
      };
      # 该无线为 Wi-Fi 7(MT7925)，5GHz 支持 EHT(AP)。160MHz 虽可启动（实测），但 CN 下
      # 必入 DFS(52–64)，而固件不支持 RDD 雷达检测（SET_RDD_CTRL 超时），无法合法运行，
      # 故固定非 DFS 的 EHT80 ch149。
      wifi7 = {
        enable = true;
        operatingChannelWidth = "80";
      };

      networks.wlp194s0 = {
        ssid = "maco";
        authentication = {
          mode = "wpa3-sae";
          saePasswords = [
            { passwordFile = config.sops.secrets.wifi-hotspot-password.path; }
          ];
        };
      };
    };
  };

  # hostapd 须等 networkd 建好 br-lan 再桥接。
  systemd.services.hostapd.after = [ "systemd-networkd.service" ];

  # dnsmasq 同样依赖 networkd 建好 br-lan。
  systemd.services.dnsmasq.after = [ "systemd-networkd.service" ];

  # DAE 同时接管 LAN 与本机：lan_interface 包局域网客户端，wan_interface 包本机流量。
  services.dae = {
    enable = true;

    package = daeuniverse.packages.${pkgs.stdenv.hostPlatform.system}.dae-unstable;

    configFile = config.sops.templates."dae.dae".path;

    # DAE 自身不打开 NixOS firewall 端口。
    openFirewall.enable = false;
  };

  # 不随 multi-user.target 自启，仅由 buaa-login 认证成功后拉起。
  systemd.services.dae.wantedBy = lib.mkForce [ ];
  systemd.services.dae.serviceConfig.Restart = "on-failure";

  # 每 15 分钟在 WAN 认证，成功后拉起 DAE。
  services.buaa-login = {
    enable = true;
    credentialsFile = config.sops.secrets.buaa-login.path;
    interval = "15min";
  };

  systemd.services.buaa-login.unitConfig.OnSuccess = [ "dae.service" ];
}
