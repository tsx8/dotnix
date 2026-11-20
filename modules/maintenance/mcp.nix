{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      upstream = inputs.mcp-nixos.lib.mkMcpNixos { inherit pkgs; };
    in
    {
      packages = {
        mcp-dotnix = pkgs.callPackage ../../packages/mcp-dotnix/package.nix {
          python3Packages = upstream.pythonPackages;
        };

        mcp-nixos = upstream.overrideAttrs (old: {
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
