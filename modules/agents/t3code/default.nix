{
  config,
  inputs,
  ...
}:
let
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
      # Linger serves the phone before KDE login and starts other user default.target units too.
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
