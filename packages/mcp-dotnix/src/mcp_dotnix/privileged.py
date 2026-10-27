from __future__ import annotations

import json
from pathlib import Path
import subprocess
import syslog
import tempfile
from typing import TypedDict

from mcp_dotnix.core import redact_text

PKEXEC = "/run/wrappers/bin/pkexec"
PRIVILEGED_RUNNER = "@privileged_runner@"
OUTPUT_LIMIT = 32768
DEFAULT_TIMEOUT = 600
MAX_TIMEOUT = 600


class PrivilegedResult(TypedDict):
    exit_code: int | None
    stdout: str
    stderr: str
    truncated: bool
    timed_out: bool
    outcome_unknown: bool


def _log_request(
    program: str, args: list[str], cwd: str, reason: str, impact: str
) -> None:
    payload = json.dumps(
        {
            "event": "run_privileged",
            "user": "root",
            "program": redact_text(program)[0],
            "args": [redact_text(arg)[0] for arg in args],
            "cwd": redact_text(cwd)[0],
            "reason": redact_text(reason)[0],
            "impact": redact_text(impact)[0],
        },
        ensure_ascii=False,
    )
    try:
        syslog.openlog("mcp-dotnix", syslog.LOG_PID, syslog.LOG_USER)
        syslog.syslog(syslog.LOG_INFO, payload)
    except OSError:
        pass


def run_privileged(
    program: str,
    args: list[str],
    cwd: str,
    reason: str,
    impact: str,
    timeout: int = DEFAULT_TIMEOUT,
) -> PrivilegedResult:
    for value in [program, cwd, *args]:
        if "\0" in value:
            raise ValueError("program, cwd and arguments must not contain NUL")
    if not Path(program).is_absolute() or not Path(cwd).is_absolute():
        raise ValueError("program and cwd must be absolute paths")
    if not 1 <= timeout <= MAX_TIMEOUT:
        raise ValueError(f"timeout must be between 1 and {MAX_TIMEOUT} seconds")
    _log_request(program, args, cwd, reason, impact)
    command = [PKEXEC, "--disable-internal-agent", "--user", "root", PRIVILEGED_RUNNER, cwd, program, *args]
    timed_out = False
    # File-backed capture bounds memory for commands with large output.
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        try:
            completed = subprocess.run(
                command,
                stdin=subprocess.DEVNULL,
                stdout=stdout, stderr=stderr, check=False,
                timeout=timeout,
            )
            exit_code = completed.returncode
        except subprocess.TimeoutExpired:
            # Killing pkexec does not prove the root child stopped.
            timed_out = True
            exit_code = None
        stdout.seek(0)
        stderr.seek(0)
        out = stdout.read(OUTPUT_LIMIT + 1)
        err = stderr.read(OUTPUT_LIMIT + 1)
    return {
        "exit_code": exit_code,
        "stdout": redact_text(out[:OUTPUT_LIMIT].decode("utf-8", errors="replace"))[0],
        "stderr": redact_text(err[:OUTPUT_LIMIT].decode("utf-8", errors="replace"))[0],
        "truncated": len(out) > OUTPUT_LIMIT or len(err) > OUTPUT_LIMIT,
        "timed_out": timed_out,
        "outcome_unknown": timed_out,
    }
