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

  services.resolved = {
    enable = true;
    settings.Resolve = {
      LLMNR = false;
      MulticastDNS = false;
    };
  };

  services.dnsmasq = {
    enable = true;

    resolveLocalQueries = false;

    settings = {
      interface = "br-lan";
      bind-dynamic = true;
      no-resolv = true;

      domain-needed = true;

      server = [ "127.0.0.53" ];

      dhcp-range = [ "192.168.77.100,192.168.77.254,12h" ];
      dhcp-option = [
        "option:router,192.168.77.1"
        "option:dns-server,192.168.77.1"
      ];
    };
  };

  systemd.network.netdevs."br-lan" = {
    netdevConfig = {
      Name = "br-lan";
      Kind = "bridge";
    };
  };

  systemd.network.networks."30-eno1" = {
    matchConfig.Name = "eno1";
    networkConfig = {
      DHCP = "ipv4";
      LinkLocalAddressing = "ipv4";
    };
  };

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

    networkConfig = {
      Bridge = "br-lan";
      LinkLocalAddressing = false;
    };
  };

  systemd.network.wait-online.ignoredInterfaces = [
    "enp196s0"
    "br-lan"
  ];

  services.hostapd = {
    enable = true;

    radios.wlp194s0 = {
      band = "5g";
      channel = 149;
      countryCode = "CN";

      settings = {
        bridge = "br-lan";
        vht_oper_centr_freq_seg0_idx = 155;
        he_oper_centr_freq_seg0_idx = 155;
        eht_oper_centr_freq_seg0_idx = 155;
      };

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

  systemd.services.hostapd.after = [ "systemd-networkd.service" ];
  systemd.services.dnsmasq.after = [ "systemd-networkd.service" ];

  services.dae = {
    enable = true;

    package = daeuniverse.packages.${pkgs.stdenv.hostPlatform.system}.dae-unstable;

    configFile = config.sops.templates."dae.dae".path;

    openFirewall.enable = false;
  };

  systemd.services.dae.wantedBy = lib.mkForce [ ];
  systemd.services.dae.serviceConfig.Restart = "on-failure";

  services.buaa-login = {
    enable = true;
    credentialsFile = config.sops.secrets.buaa-login.path;
    interval = "15min";
  };

  systemd.services.buaa-login.unitConfig.OnSuccess = [ "dae.service" ];
}
