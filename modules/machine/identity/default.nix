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

    sops.secrets.gh-auth-token = { };
    sops.templates."nix.conf" = {
      content = ''
        access-tokens = github.com=${config.sops.placeholder.gh-auth-token}
      '';
      owner = userName;
    };

    # Creating ~/.ssh via sops would leave parent directories owned by root.
    sops.secrets.ssh-dmit = {
      owner = userName;
      mode = "0400";
    };

    # A Home Manager SSH config would copy the private address into the Nix store.
    sops.templates."ssh-config".content = ''
      Host dmit
        HostName ${config.sops.placeholder.dae-node-ip}
        Port 2222
        User root
        IdentityFile ~/.ssh/id_dmit
        IdentitiesOnly yes
    '';
    sops.templates."ssh-config".owner = userName;

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
      "d ${config.users.users.${userName}.home}/.ssh 0700 ${userName} ${
        config.users.users.${userName}.group
      } -"
    ];
    environment.systemPackages = [ pkgs.sops ];
  };

  dotnix.modules.home = { config, ... }: {
    home.file.".config/sops/age/keys.txt".source =
      config.lib.file.mkOutOfStoreSymlink "/var/lib/sops-nix/key.txt";
    home.file.".config/nix/nix.conf".source =
      config.lib.file.mkOutOfStoreSymlink "/run/secrets/rendered/nix.conf";
    home.file.".ssh/config".source =
      config.lib.file.mkOutOfStoreSymlink "/run/secrets/rendered/ssh-config";
    home.file.".ssh/id_dmit".source = config.lib.file.mkOutOfStoreSymlink "/run/secrets/ssh-dmit";
  };

  perSystem = { pkgs, ... }: {
    packages = {
      inherit (pkgs) age sops;
    };
  };
}
