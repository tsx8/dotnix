from __future__ import annotations

from fastmcp import FastMCP
from fastmcp.tools import ToolResult
from mcp.types import ToolAnnotations

from mcp_dotnix import core, privileged

mcp = FastMCP(
    "mcp-dotnix",
    instructions=(
        "NixOS diagnostics and polkit-authenticated privileged execution for dotnix. "
        "Diagnostic tools are read-only. Each run_privileged call requires "
        "desktop polkit authentication before root execution. "
        "Clients should not add a separate approval prompt. "
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


def _privileged_text(result: privileged.PrivilegedResult) -> str:
    status = (
        "timed out before exit"
        if result["timed_out"]
        else f"exit code: {result['exit_code']}"
    )
    parts = [
        status,
        "stdout:\n" + (result["stdout"].rstrip("\n") or "(empty)"),
        "stderr:\n" + (result["stderr"].rstrip("\n") or "(empty)"),
    ]
    if result["timed_out"]:
        parts.append(
            "outcome unknown: pkexec was killed; a privileged child may still be running; "
            "verify system state before retrying"
        )
    if result["truncated"]:
        parts.append(f"output truncated at {privileged.OUTPUT_LIMIT} bytes per stream")
    return "\n\n".join(parts)


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


@mcp.tool(
    name="run_privileged",
    annotations=ToolAnnotations(
        readOnlyHint=False, destructiveHint=True, idempotentHint=False, openWorldHint=True,
    ),
)
def run_privileged(
    program: str,
    args: list[str],
    cwd: str,
    reason: str,
    impact: str,
    timeout: int = privileged.DEFAULT_TIMEOUT,
) -> privileged.PrivilegedResult:
    """Run a command as root after desktop polkit authentication, returning its exit code and output.

    Use absolute program and cwd paths. Arguments are passed without shell expansion.
    Each call requires authentication; authorization is not retained.
    Requires the NixOS pkexec wrapper and the dedicated entry's polkit rule.
    Fails if authentication is unavailable; no terminal authentication or sudo fallback.
    Command stdin is closed; pkexec filters the environment and the entry sets a system PATH.
    The server stops waiting after timeout seconds and kills pkexec; a privileged child
    may continue, so a timeout is reported as outcome unknown. Client cancellation also
    does not guarantee the command has stopped.
    Existing restrictions on system activation, secrets and other operations apply.
    The request reason and impact are recorded in the journal under the mcp-dotnix tag.

    Args:
        program: Absolute path of the program to run as root.
        args: Exact arguments passed to the program.
        cwd: Absolute working directory.
        reason: Explain why this operation needs root privileges.
        impact: Describe affected files, services or system state and expected changes.
        timeout: Server-side wait limit in seconds (1-600), including authentication.
            Defaults to 600; lower it only for commands known to finish quickly.
    """
    if not reason.strip() or not impact.strip():
        raise ValueError("reason and impact must explain the privilege request")
    if not 1 <= timeout <= privileged.MAX_TIMEOUT:
        raise ValueError(
            f"timeout must be between 1 and {privileged.MAX_TIMEOUT} seconds"
        )
    result = privileged.run_privileged(program, args, cwd, reason, impact, timeout)
    return ToolResult(content=_privileged_text(result), structured_content=result)


def main() -> None:
    mcp.run(transport="stdio", show_banner=False)


if __name__ == "__main__":
    main()
