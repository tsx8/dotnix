{
  python3Packages,
  fastmcp,
}:

python3Packages.buildPythonApplication {
  pname = "mcp-dotnix";
  version = "0.3.0";
  pyproject = true;

  src = ./.;

  build-system = [
    python3Packages.hatchling
  ];

  dependencies = [
    # Injected from mcp-nixos's vendored fastmcp 4 stack: nixpkgs fastmcp 3.x
    # is marked broken against python mcp 2.
    fastmcp
  ];

  pythonImportsCheck = [
    "mcp_dotnix.server"
  ];

  meta = {
    description = "Read-only NixOS diagnostics for dotnix";
    mainProgram = "mcp-dotnix";
  };
}
