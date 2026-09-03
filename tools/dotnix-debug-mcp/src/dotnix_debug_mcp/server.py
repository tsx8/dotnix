from __future__ import annotations

from typing import Any

from mcp.server.fastmcp import FastMCP
from mcp.types import ToolAnnotations

from . import core

mcp = FastMCP(
    "dotnix-debug",
    instructions=(
        "Read-only NixOS diagnostics for dotnix. Tools never mutate system state, "
        "run sudo, or read arbitrary files. Journal output is best-effort redacted "
        "and must still be treated as potentially sensitive."
    ),
)
_read_only = ToolAnnotations(
    readOnlyHint=True,
    destructiveHint=False,
    idempotentHint=True,
    openWorldHint=False,
)


@mcp.tool(name="system_status", annotations=_read_only)
def system_status() -> dict[str, Any]:
    """Return current NixOS, systemd, failed-unit, and generation-link status."""
    return core.system_status()


@mcp.tool(name="unit_status", annotations=_read_only)
def unit_status(unit: str) -> dict[str, Any]:
    """Return fixed properties for one exact systemd unit name."""
    return core.unit_status(unit)


@mcp.tool(name="unit_journal", annotations=_read_only)
def unit_journal(unit: str, lines: int = 80, priority: int = 7) -> dict[str, Any]:
    """Read a bounded journal for one unit in the current boot."""
    return core.unit_journal(unit, lines, priority)


@mcp.tool(name="nixos_generations", annotations=_read_only)
def nixos_generations(limit: int = 20) -> dict[str, Any]:
    """List recent NixOS system generations from read-only profile links."""
    return core.nixos_generations(limit)


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
