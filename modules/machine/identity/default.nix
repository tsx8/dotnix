{ config, inputs, ... }:

let
  userName = config.dotnix.host.userName;
in
{
  dotnix.modules.nixos = { config, pkgs, ... }: {
    imports = [ inputs.sops-nix.nixosModules.sops ];

    sops = {
      defaultSopsFile = ./secrets.yaml;
      age = {
        keyFile = "/var/lib/sops-nix/key.txt";
        generateKey = false;
      };
      secrets.user-passwd-hash.neededForUsers = true;
    };

    users.groups.sops = { };
    users.users.${userName} = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "sops"
      ];
      hashedPasswordFile = config.sops.secrets.user-passwd-hash.path;
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/sops-nix 0750 root sops -"
      "z /var/lib/sops-nix/key.txt 0440 root sops -"
    ];
    environment.systemPackages = [ pkgs.sops ];
  };

  dotnix.modules.home = { config, ... }: {
    home.file.".config/sops/age/keys.txt".source =
      config.lib.file.mkOutOfStoreSymlink "/var/lib/sops-nix/key.txt";
  };

  perSystem = { pkgs, ... }: {
    packages = {
      inherit (pkgs) age sops;
    };
  };
}
