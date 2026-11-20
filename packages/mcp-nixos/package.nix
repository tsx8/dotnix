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
