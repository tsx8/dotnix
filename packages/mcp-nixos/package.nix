# Packaged in-repo from the upstream flake source: upstream's own package output builds
# through its fastmcp4 package-set extension, which recurses on nixpkgs revisions that ship
# python mcp >= 2. Building here with the shared vendored fastmcp 4 keeps one python set.
{
  lib,
  python3Packages,
  fastmcp,
  mcpNixosSrc,
}:
let
  pyproject = lib.importTOML "${mcpNixosSrc}/pyproject.toml";
in
python3Packages.buildPythonApplication {
  pname = pyproject.project.name;
  inherit (pyproject.project) version;
  pyproject = true;

  src = mcpNixosSrc;

  # Upstream calls nix flake archive when querying flake inputs but omits the lock protection flags.
  postPatch = ''
    substituteInPlace mcp_nixos/sources/flake_inputs.py \
      --replace-fail \
        '["flake", "archive", "--json"]' \
        '["flake", "archive", "--json", "--no-update-lock-file", "--no-write-lock-file"]'
  '';

  build-system = [ python3Packages.hatchling ];

  dependencies = [
    fastmcp
    python3Packages.requests
    python3Packages.beautifulsoup4
  ];

  pythonRelaxDeps = true;
  pythonImportsCheck = [ "mcp_nixos" ];

  meta = {
    inherit (pyproject.project) description;
    homepage = "https://github.com/utensils/mcp-nixos";
    license = lib.licenses.mit;
    mainProgram = "mcp-nixos";
  };
}
