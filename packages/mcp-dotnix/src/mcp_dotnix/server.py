from __future__ import annotations

from fastmcp import FastMCP
from fastmcp.tools import ToolResult
from mcp.types import ToolAnnotations

from mcp_dotnix import core

mcp = FastMCP(
    "mcp-dotnix",
    instructions=(
        "Read-only NixOS diagnostics for dotnix. "
        "Output is best-effort redacted and may still contain sensitive data."
    ),
)
_read_only = ToolAnnotations(
    readOnlyHint=True,
    destructiveHint=False,
    idempotentHint=True,
    openWorldHint=False,
)


def _journal_text(result: core.JournalResult) -> str:
    header = (
        f"{result['unit']} (boot {result['boot']}): "
        f"{result['returned']} of {result['available']} entries"
    )
    notes = []
    if result["omitted"]:
        notes.append(f"{result['omitted']} omitted at {result['output_byte_limit']} bytes")
    if result["parse_errors"]:
        notes.append(f"parse errors: {result['parse_errors']}")
    if result["truncated_messages"]:
        notes.append(f"truncated messages: {result['truncated_messages']}")
    if result["redactions"]:
        notes.append(f"redactions: {result['redactions']}")
    if notes:
        header += " (" + ", ".join(notes) + ")"
    lines = [header]
    for entry in result["entries"]:
        lines.append(
            f"{entry['timestamp'] or '-'} {entry['identifier'] or '-'}: {entry['message']}"
        )
    return "\n".join(lines)


@mcp.tool(name="system_status", annotations=_read_only)
def system_status() -> core.SystemStatus:
    """Return current NixOS, systemd, failed-unit, and generation-link status."""
    return core.system_status()


@mcp.tool(name="unit_status", annotations=_read_only)
def unit_status(unit: str) -> core.UnitStatus:
    """Return fixed properties for one exact systemd unit name."""
    return core.unit_status(unit)


@mcp.tool(name="unit_journal", annotations=_read_only)
def unit_journal(
    unit: str, lines: int = 80, priority: int = 7, boot: str = "current"
) -> core.JournalResult:
    """Read a bounded journal for one unit in the current or a previous boot."""
    result = core.unit_journal(unit, lines, priority, boot)
    return ToolResult(content=_journal_text(result), structured_content=result)


@mcp.tool(name="kernel_log", annotations=_read_only)
def kernel_log(
    lines: int = 80, priority: int = 7, boot: str = "current"
) -> core.JournalResult:
    """Read bounded kernel messages from the current or a previous boot."""
    result = core.kernel_log(lines, priority, boot)
    return ToolResult(content=_journal_text(result), structured_content=result)


@mcp.tool(name="boot_list", annotations=_read_only)
def boot_list(limit: int = 20) -> core.BootResult:
    """List recent boots from the journal, most recent first."""
    return core.boot_list(limit)


@mcp.tool(name="disk_status", annotations=_read_only)
def disk_status() -> core.DiskStatusResult:
    """Return block device layout from lsblk and mount table from /proc/mounts."""
    return core.disk_status()


@mcp.tool(name="network_status", annotations=_read_only)
def network_status() -> core.NetworkStatusResult:
    """Return network interface addresses and main routing table."""
    return core.network_status()


@mcp.tool(name="nixos_generations", annotations=_read_only)
def nixos_generations(limit: int = 20) -> core.GenerationResult:
    """List recent NixOS system generations from read-only profile links."""
    return core.nixos_generations(limit)


def main() -> None:
    mcp.run(transport="stdio", show_banner=False)


if __name__ == "__main__":
    main()
