from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile
from typing import TypedDict

from mcp_dotnix.core import redact_text

SUDO = "/run/wrappers/bin/sudo"
PRIVILEGED_RUNNER = "@privileged_runner@"
OUTPUT_LIMIT = 32768


class PrivilegedResult(TypedDict):
    exit_code: int
    stdout: str
    stderr: str
    truncated: bool


def run_privileged(program: str, args: list[str], cwd: str) -> PrivilegedResult:
    for value in [program, cwd, *args]:
        if "\0" in value:
            raise ValueError("program, cwd and arguments must not contain NUL")
    if not Path(program).is_absolute() or not Path(cwd).is_absolute():
        raise ValueError("program and cwd must be absolute paths")
    # Ignore cached credentials so a missing NOPASSWD rule fails without prompting.
    command = [SUDO, "-k", "-n", "-u", "root", "--", PRIVILEGED_RUNNER, cwd, program, *args]
    # File-backed capture bounds memory for commands with large output.
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        completed = subprocess.run(
            command,
            stdin=subprocess.DEVNULL,
            stdout=stdout, stderr=stderr, check=False,
        )
        stdout.seek(0)
        stderr.seek(0)
        out = stdout.read(OUTPUT_LIMIT + 1)
        err = stderr.read(OUTPUT_LIMIT + 1)
    return {
        "exit_code": completed.returncode,
        "stdout": redact_text(out[:OUTPUT_LIMIT].decode("utf-8", errors="replace"))[0],
        "stderr": redact_text(err[:OUTPUT_LIMIT].decode("utf-8", errors="replace"))[0],
        "truncated": len(out) > OUTPUT_LIMIT or len(err) > OUTPUT_LIMIT,
    }
