{ config, self, ... }:
let
  userName = config.dotnix.host.userName;
in
{
  dotnix.modules.nixos = { pkgs, ... }: {
    security.polkit = {
      enable = true;
      enablePkexecWrapper = true;
      extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id === "org.freedesktop.policykit.exec" &&
              action.lookup("program") === ${builtins.toJSON "${self.packages.${pkgs.stdenv.hostPlatform.system}.mcp-dotnix.privilegedRunner}"}) {
            if (subject.user === ${builtins.toJSON userName} && action.lookup("user") === "root") {
              // The authorization cache does not distinguish command arguments, so AUTH_ADMIN_KEEP must not be used.
              return polkit.Result.AUTH_ADMIN;
            }
            return polkit.Result.NO;
          }
        });
      '';
    };
  };

  perSystem =
    { pkgs, inputs', ... }:
    {
      packages = {
        mcp-dotnix = pkgs.callPackage ../../packages/mcp-dotnix/package.nix { };

        # Upstream calls nix flake archive when querying flake inputs but omits the lock protection flags.
        mcp-nixos = inputs'.mcp-nixos.packages.mcp-nixos.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            substituteInPlace mcp_nixos/sources/flake_inputs.py \
              --replace-fail \
                '["flake", "archive", "--json"]' \
                '["flake", "archive", "--json", "--no-update-lock-file", "--no-write-lock-file"]'
          '';
        });
      };
    };
}
