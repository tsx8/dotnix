{ inputs, ... }:
{
  dotnix.modules.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      wanInterface = "eno1";
      lanInterface = "br-lan";
      lanEthernetInterface = "enp196s0";
      wifiInterface = "wlp194s0";
      lanAddress = "192.168.77.1";
      campusDns = "202.112.128.50";
    in
    {
      imports = [
        inputs.buaa-login.nixosModules.default
        inputs.daeuniverse.nixosModules.dae
      ];

      hardware.facter.detected.dhcp.enable = false;
      environment.systemPackages = [ pkgs.iw ];

      sops.secrets = {
        dae-nodes = { };
        buaa-login = { };
        wifi-hotspot-password = { };
      };

      sops.templates."dae.dae".content = ''
        global {
          lan_interface: ${lanInterface}
          wan_interface: ${wanInterface}
          log_level: info
          allow_insecure: false
          auto_config_kernel_parameter: true
          dial_mode: domain
        }

        dns {
          ipversion_prefer: 4

          upstream {
            buaadns: 'udp://${campusDns}:53'
            googledns: 'tcp+udp://dns.google.com:53'
          }

          routing {
            request {
              fallback: buaadns
            }
            response {
              upstream(googledns) -> accept
              ip(geoip:private) && !qname(geosite:cn) -> googledns
              fallback: accept
            }
          }
        }

        group {
          proxy {
            policy: fixed(0)
          }
        }

        routing {
          dip(224.0.0.0/3) -> direct
          dip(${campusDns}) && l4proto(udp) && dport(53) -> must_direct
          l4proto(udp) && dport(443) -> block
          dip(geoip:private) -> direct
          dip(geoip:cn) -> direct
          domain(geosite:cn) -> direct
          fallback: proxy
        }
      ''
      + "\n"
      + config.sops.placeholder.dae-nodes;

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
          interface = lanInterface;
          bind-dynamic = true;
          no-resolv = true;

          domain-needed = true;

          server = [ "127.0.0.53" ];

          dhcp-range = [ "192.168.77.100,192.168.77.254,12h" ];
          dhcp-option = [
            "option:router,${lanAddress}"
            "option:dns-server,${lanAddress}"
          ];
        };
      };

      systemd.network.netdevs.${lanInterface} = {
        netdevConfig = {
          Name = lanInterface;
          Kind = "bridge";
        };
      };

      systemd.network.networks."30-${wanInterface}" = {
        matchConfig.Name = wanInterface;
        networkConfig = {
          DHCP = "ipv4";
          LinkLocalAddressing = "ipv4";
        };
      };

      systemd.network.networks."30-${lanInterface}" = {
        matchConfig.Name = lanInterface;
        address = [ "${lanAddress}/24" ];
        networkConfig = {
          IPMasquerade = "ipv4";
          IPv4Forwarding = true;
          LinkLocalAddressing = "ipv4";
        };
      };

      systemd.network.networks."40-${lanEthernetInterface}" = {
        matchConfig.Name = lanEthernetInterface;

        networkConfig = {
          Bridge = lanInterface;
          LinkLocalAddressing = false;
        };
      };

      systemd.network.wait-online.ignoredInterfaces = [
        lanEthernetInterface
        lanInterface
      ];

      services.hostapd = {
        enable = true;

        radios.${wifiInterface} = {
          band = "5g";
          channel = 149;
          countryCode = "CN";

          settings = {
            bridge = lanInterface;
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

          networks.${wifiInterface} = {
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

        package = inputs.daeuniverse.packages.${pkgs.stdenv.hostPlatform.system}.dae-unstable;

        configFile = config.sops.templates."dae.dae".path;

        openFirewall.enable = false;
      };

      systemd.services.dae.wantedBy = lib.mkForce [ ];
      systemd.services.dae.serviceConfig.Restart = "on-failure";

      services.buaa-login = {
        enable = true;
        credentialsFile = config.sops.secrets.buaa-login.path;
        interval = "15min";
        interface = wanInterface;
      };

      systemd.services.buaa-login.unitConfig.OnSuccess = [ "dae.service" ];

    };
}
