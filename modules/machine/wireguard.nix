{
  dotnix.modules.nixos =
    { config, ... }:
    {
      sops.secrets.wg-dmit-private-key = { };

      sops.templates."wg-dmit.conf" = {
        owner = "root";
        mode = "0400";
        restartUnits = [ "wg-quick-wg-dmit.service" ];
        content = ''
          [Interface]
          Address = 100.64.0.2/32
          PrivateKey = ${config.sops.placeholder.wg-dmit-private-key}

          [Peer]
          PublicKey = jjjUwGA2durYXynhai54fYkToFFUT5YawRFZaPHNqSw=
          Endpoint = ${config.sops.placeholder.dae-node-ip}:51820
          AllowedIPs = 100.64.0.1/32
          PersistentKeepalive = 25
        '';
      };

      networking.wg-quick.interfaces.wg-dmit.configFile = config.sops.templates."wg-dmit.conf".path;
    };
}
