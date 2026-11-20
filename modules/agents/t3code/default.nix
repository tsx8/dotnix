{
  config,
  inputs,
  ...
}:
let
  # Flake outputs captured before the inner NixOS/Home Manager modules shadow `config`.
  packagesFor = system: config.flake.packages.${system};
in
{
  perSystem =
    { pkgs, system, ... }:
    {
      packages.t3code-nightly = pkgs.callPackage ../../../packages/t3code-nightly/package.nix {
        t3code = inputs.llm-agents.packages.${system}.t3code;
      };
    };

  dotnix.modules.nixos =
    { pkgs, ... }:
    let
      t3Pkg = (packagesFor pkgs.stdenv.hostPlatform.system).t3code-nightly;
    in
    {
      environment.systemPackages = [
        t3Pkg
        t3Pkg.desktop
      ];
      # T3 serves the phone while nobody is logged into KDE; this also starts the user's other default.target services.
      users.users.${config.dotnix.host.userName}.linger = true;
    };

  dotnix.modules.home =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      t3Pkg = (packagesFor pkgs.stdenv.hostPlatform.system).t3code-nightly;
    in
    {
      programs.t3code = {
        enable = true;
        package = t3Pkg;
        mutableUserSettings = true;
        userSettings = {
          enableProviderUpdateChecks = false;
          providerInstances = {
            pi = {
              driver = "pi";
              enabled = true;
              config = {
                enabled = true;
                binaryPath = "/run/current-system/sw/bin/pi";
              };
            };
            codex = {
              driver = "codex";
              enabled = false;
            };
            claudeAgent = {
              driver = "claudeAgent";
              enabled = false;
            };
          };
        };
        server = {
          enable = true;
          extraArgs = [
            "--host"
            "127.0.0.1"
            "--port"
            "3773"
            "--no-browser"
          ];
        };
      };

      # linger starts the user manager before login, where systemd's own PATH has no git, shell, or
      # project tools. Give the service the session PATH instead of relying on a desktop login.
      systemd.user.services.t3code.Service.Environment = [
        "PATH=${
          lib.concatStringsSep ":" [
            "${config.home.homeDirectory}/.nix-profile/bin"
            "/nix/profile/bin"
            "${config.home.homeDirectory}/.local/state/nix/profile/bin"
            "/etc/profiles/per-user/${config.home.username}/bin"
            "/nix/var/nix/profiles/default/bin"
            "/run/current-system/sw/bin"
            "/run/wrappers/bin"
          ]
        }"
      ];

      # The desktop app loads its bundled UI and pairs with the service instead of starting a second server.
      # This HM version has no option for desktop-settings.json, so merge the one key with the generated merger.
      home.activation.t3codeDesktopSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] (
        lib.hm.generators.mkImpureConfigMerger {
          inherit pkgs;
          format = "json";
          empty = "{}";
          jqOperation = "$dynamic * $static";
          mode = "600";
          path = "${config.home.homeDirectory}/.t3/userdata/desktop-settings.json";
          staticSettings = (pkgs.formats.json { }).generate "t3code-desktop-settings" {
            localEnvironmentEnabled = false;
          };
        }
      );
    };
}
