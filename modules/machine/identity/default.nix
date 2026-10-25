{ config, inputs, ... }:

let
  userName = config.dotnix.host.userName;
in
{
  dotnix.modules.nixos = { config, pkgs, ... }: {
    imports = [ inputs.sops-nix.nixosModules.sops ];

    # nixpkgs dropped the EOL buildGo125Module, but sops-nix upstream still hardcodes it to build
    # sops-install-secrets; alias the current builder as a stopgap and drop this once upstream migrates.
    nixpkgs.overlays = [
      (_: prev: { buildGo125Module = prev.buildGoModule; })
    ];

    sops = {
      defaultSopsFile = ./secrets.yaml;
      age = {
        keyFile = "/var/lib/sops-nix/key.txt";
        generateKey = false;
      };
      secrets.user-passwd-hash.neededForUsers = true;
    };

    # Anonymous GitHub API access allows 60 requests/h; flake input resolution exhausts it easily and then
    # silently reuses cached versions for the whole batch. The token is rendered into the user-level nix.conf
    # for every nix command running as this user; the raw secret is root-only, only the rendered artifact is user-readable.
    sops.secrets.gh-auth-token = { };
    sops.templates."nix.conf" = {
      content = ''
        access-tokens = github.com=${config.sops.placeholder.gh-auth-token}
      '';
      owner = userName;
    };

    # VPS access key stays in sops under /run/secrets; ~/.ssh links to it below so the directory
    # keeps a single owner (sops-install-secrets creates parent directories as root).
    sops.secrets.ssh-dmit = {
      owner = userName;
      mode = "0400";
    };

    # The address stays a sops placeholder so it never reaches the store, which rules out
    # programs.ssh: that module writes its config, address included, into a store path.
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
    # Points to the sops-nix rendered artifact; the symlink stays out of the store so no secret lands in plaintext config.
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
