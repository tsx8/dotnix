from __future__ import annotations

from fastmcp import FastMCP
from mcp.types import ToolAnnotations

from mcp_dotnix import core, privileged

mcp = FastMCP(
    "mcp-dotnix",
    instructions=(
        "NixOS diagnostics and explicitly approved privileged execution for dotnix. "
        "Diagnostic tools are read-only. The client must require approval for "
        "run_privileged, showing its command, cwd, reason and impact before execution. "
        "The dedicated root execution entry uses passwordless sudo. "
        "Output is best-effort redacted and may still contain sensitive data."
    ),
)
_read_only = ToolAnnotations(
    readOnlyHint=True,
    destructiveHint=False,
    idempotentHint=True,
    openWorldHint=False,
)


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
    return core.unit_journal(unit, lines, priority, boot)


@mcp.tool(name="kernel_log", annotations=_read_only)
def kernel_log(
    lines: int = 80, priority: int = 7, boot: str = "current"
) -> core.JournalResult:
    """Read bounded kernel messages from the current or a previous boot."""
    return core.kernel_log(lines, priority, boot)


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


@mcp.tool(
    name="run_privileged",
    annotations=ToolAnnotations(
        readOnlyHint=False, destructiveHint=True, idempotentHint=False, openWorldHint=True,
    ),
)
def run_privileged(
    program: str, args: list[str], cwd: str, reason: str, impact: str,
) -> privileged.PrivilegedResult:
    """Run a command as root without a password after client approval, returning its exit code and output.

    Use absolute program and cwd paths. Arguments are passed without shell expansion.
    The client must show the command, cwd, reason and impact before approval.
    Requires the dedicated entry's NOPASSWD rule; fails without prompting if unavailable.
    Command stdin is closed and sudo filters the inherited environment.
    Client cancellation or timeout does not guarantee the command has stopped.
    Existing restrictions on system activation, secrets and other operations apply.

    Args:
        program: Absolute path of the program to run as root.
        args: Exact arguments passed to the program.
        cwd: Absolute working directory.
        reason: Explain why this operation needs root privileges.
        impact: Describe affected files, services or system state and expected changes.
    """
    if not reason.strip() or not impact.strip():
        raise ValueError("reason and impact must explain the privilege request")
    return privileged.run_privileged(program, args, cwd)


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
