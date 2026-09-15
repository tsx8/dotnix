{ python3Packages, writeShellScript }:

let
  privilegedRunner = writeShellScript "mcp-dotnix-run-privileged" ''
    set -euo pipefail
    if [[ $# -lt 2 || $1 != /* || $2 != /* ]]; then
      echo "usage: mcp-dotnix-run-privileged /cwd /program [args...]" >&2
      exit 2
    fi
    cd -- "$1"
    shift
    exec -- "$@"
  '';
in
python3Packages.buildPythonApplication {
  pname = "mcp-dotnix";
  version = "0.2.0";
  pyproject = true;

  src = ./.;

  postPatch = ''
    substituteInPlace src/mcp_dotnix/privileged.py \
      --replace-fail '@privileged_runner@' '${privilegedRunner}'
  '';

  passthru = { inherit privilegedRunner; };

  build-system = [
    python3Packages.hatchling
  ];

  dependencies = [
    python3Packages.fastmcp
  ];

  pythonImportsCheck = [
    "mcp_dotnix.server"
  ];

  meta = {
    description = "NixOS diagnostics and user-approved privileged execution for dotnix";
    mainProgram = "mcp-dotnix";
  };
}
