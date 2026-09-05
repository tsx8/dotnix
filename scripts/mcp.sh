#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
mcp-dotnix) attr="mcp-dotnix" ;;
mcp-nixos) attr="mcp-nixos" ;;
*)
  echo "usage: mcp.sh mcp-dotnix|mcp-nixos" >&2
  exit 2
  ;;
esac

root="$(git rev-parse --show-toplevel)"
cd "$root"

exec nix run --no-update-lock-file --no-write-lock-file ".#$attr"
