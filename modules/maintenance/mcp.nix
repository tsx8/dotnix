{
  config,
  inputs,
  self,
  ...
}:
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
    { pkgs, ... }:
    let
      fastmcp = pkgs.callPackage ../../packages/fastmcp4/package.nix {
        mcpNixosSrc = inputs.mcp-nixos;
      };
    in
    {
      packages = {
        mcp-dotnix = pkgs.callPackage ../../packages/mcp-dotnix/package.nix { inherit fastmcp; };

        mcp-nixos = pkgs.callPackage ../../packages/mcp-nixos/package.nix {
          inherit fastmcp;
          mcpNixosSrc = inputs.mcp-nixos;
        };
      };
    };
}
