from __future__ import annotations

import datetime as dt
import glob
import json
import os
import platform
import re
import socket
import subprocess
from pathlib import Path
from typing import TypeAlias, TypedDict, cast

SYSTEMCTL = "/run/current-system/sw/bin/systemctl"
JOURNALCTL = "/run/current-system/sw/bin/journalctl"
NIXOS_VERSION = "/run/current-system/sw/bin/nixos-version"
SYSTEM_PROFILE = Path("/nix/var/nix/profiles/system")

UNIT_SUFFIXES = (
    "service",
    "socket",
    "timer",
    "target",
    "mount",
    "path",
    "scope",
    "slice",
    "swap",
)
UNIT_RE = re.compile(r"^[A-Za-z0-9@._-]{1,128}\.(?:" + "|".join(UNIT_SUFFIXES) + r")$")
GENERATION_RE = re.compile(r"^system-(\d+)-link$")

JOURNAL_MAX_LINES = 200
JOURNAL_MESSAGE_MAX_BYTES = 2 * 1024
JOURNAL_OUTPUT_MAX_BYTES = 32 * 1024
GENERATION_MAX_LIMIT = 50

_ENV = {
    "LC_ALL": "C",
    "LANG": "C",
    "SYSTEMD_COLORS": "0",
}

JsonObject: TypeAlias = dict[str, object]
UnitStatusValue: TypeAlias = str | int | None
UnitStatus: TypeAlias = dict[str, UnitStatusValue]

_SECRET_KEY_RE = re.compile(
    r"(?i)\b(password|passphrase|api[_-]?key|secret|token|"
    + r"authorization|cookie|credential)\b(\s*[:=]\s*)[^\s,;]+"
)
_BEARER_RE = re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+")
_URL_QUERY_RE = re.compile(
    r"(?i)([?&](?:password|passphrase|api[_-]?key|secret|token|"
    + r"authorization|cookie|credential)=)[^&\s]+"
)
_PRIVATE_KEY_RE = re.compile(
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----",
    re.DOTALL,
)


class InvalidInput(ValueError):
    """An input is outside the fixed debug-tool schema."""


class FailedUnit(TypedDict):
    unit: str
    load: str
    active: str
    sub: str
    description: str


class SystemdStatus(TypedDict):
    state: str
    failed_count: int


class SystemLinks(TypedDict):
    current_system: str | None
    booted_system: str | None
    system_profile: str | None
    system_profile_generation: int | None


class SystemStatus(TypedDict):
    hostname: str
    kernel: str
    nixos_version: str | None
    systemd: SystemdStatus
    links: SystemLinks
    failed_units: list[FailedUnit]


class JournalEntry(TypedDict):
    timestamp: str | None
    priority: int | None
    identifier: str | None
    pid: int | None
    unit: str | None
    message: str
    message_truncated: bool
    redactions: int


class JournalResult(TypedDict):
    unit: str
    boot: str
    entries: list[JournalEntry]
    requested: int
    returned: int
    available: int
    omitted: int
    parse_errors: int
    redactions: int
    truncated_messages: int
    output_byte_limit: int
    sensitive_hint: bool


class GenerationEntry(TypedDict):
    generation: int
    path: str
    modified_at: str
    current: bool


class GenerationResult(TypedDict):
    current_generation: int | None
    returned: int
    generations: list[GenerationEntry]


def validate_unit(unit: object) -> str:
    if not isinstance(unit, str) or not UNIT_RE.fullmatch(unit):
        raise InvalidInput(
            "unit must be an exact systemd unit name with an allowed suffix"
        )
    if "/" in unit or "\\" in unit or ".." in unit or any(c.isspace() for c in unit):
        raise InvalidInput("unit must not contain path or whitespace characters")
    return unit


def validate_limit(limit: object, maximum: int, default: int) -> int:
    if limit is None:
        return default
    if (
        isinstance(limit, bool)
        or not isinstance(limit, int)
        or not 1 <= limit <= maximum
    ):
        raise InvalidInput(f"limit must be an integer between 1 and {maximum}")
    return limit


def validate_priority(priority: object) -> int:
    if (
        isinstance(priority, bool)
        or not isinstance(priority, int)
        or not 0 <= priority <= 7
    ):
        raise InvalidInput("priority must be an integer between 0 and 7")
    return priority


def redact_text(text: str) -> tuple[str, int]:
    count = 0

    def increment() -> None:
        nonlocal count
        count += 1

    def count_redaction(_match: re.Match[str]) -> str:
        increment()
        return "[REDACTED]"

    def count_url_redaction(match: re.Match[str]) -> str:
        increment()
        return match.group(1) + "[REDACTED]"

    def count_secret_redaction(match: re.Match[str]) -> str:
        increment()
        return match.group(1) + match.group(2) + "[REDACTED]"

    text = _PRIVATE_KEY_RE.sub(count_redaction, text)
    text = _BEARER_RE.sub(count_redaction, text)
    text = _URL_QUERY_RE.sub(count_url_redaction, text)
    text = _SECRET_KEY_RE.sub(count_secret_redaction, text)
    return text, count


def _truncate_bytes(text: str, limit: int) -> tuple[str, bool]:
    encoded = text.encode("utf-8")
    if len(encoded) <= limit:
        return text, False
    truncated = encoded[:limit].decode("utf-8", errors="ignore")
    return truncated + "[truncated]", True


def _run(command: list[str], timeout: float = 10.0) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            env=_ENV,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(f"command failed: {Path(command[0]).name}") from error


def _realpath(path: str | Path) -> str | None:
    try:
        return os.path.realpath(path)
    except OSError:
        return None


def _profile_generation(path: Path | None = None) -> int | None:
    path = SYSTEM_PROFILE if path is None else path
    try:
        match = GENERATION_RE.fullmatch(os.readlink(path))
        return int(match.group(1)) if match else None
    except OSError:
        return None


def _optional_integer(value: object) -> int | None:
    if isinstance(value, bool) or not isinstance(value, (str, int)):
        return None
    try:
        return int(value)
    except (ValueError, OverflowError):
        return None


def _optional_text(value: object) -> str | None:
    return value if isinstance(value, str) else None


def _first_text(value: JsonObject, names: tuple[str, ...]) -> str | None:
    for name in names:
        text = _optional_text(value.get(name))
        if text is not None:
            return text
    return None


def system_status() -> SystemStatus:
    state = _run([SYSTEMCTL, "is-system-running"])
    failed = _run([SYSTEMCTL, "--failed", "--no-legend", "--plain", "--no-pager"])
    version = _run([NIXOS_VERSION], timeout=5)
    failed_units: list[FailedUnit] = []
    for line in failed.stdout.splitlines():
        fields = line.split(None, 4)
        if len(fields) >= 4:
            failed_units.append(
                {
                    "unit": fields[0],
                    "load": fields[1],
                    "active": fields[2],
                    "sub": fields[3],
                    "description": fields[4] if len(fields) == 5 else "",
                }
            )

    systemd: SystemdStatus = {
        "state": state.stdout.strip() or "unknown",
        "failed_count": len(failed_units),
    }
    links: SystemLinks = {
        "current_system": _realpath("/run/current-system"),
        "booted_system": _realpath("/run/booted-system"),
        "system_profile": _realpath(SYSTEM_PROFILE),
        "system_profile_generation": _profile_generation(),
    }
    return {
        "hostname": socket.gethostname(),
        "kernel": platform.release(),
        "nixos_version": version.stdout.strip() if version.returncode == 0 else None,
        "systemd": systemd,
        "links": links,
        "failed_units": failed_units,
    }


def unit_status(unit: str) -> UnitStatus:
    unit = validate_unit(unit)
    properties = [
        "Id",
        "Description",
        "LoadState",
        "ActiveState",
        "SubState",
        "UnitFileState",
        "Result",
        "ExecMainCode",
        "ExecMainStatus",
        "ExecMainPID",
        "ExecMainStartTimestamp",
        "ExecMainExitTimestamp",
        "ActiveEnterTimestamp",
        "InactiveEnterTimestamp",
        "NRestarts",
        "InvocationID",
    ]
    result = _run(
        [SYSTEMCTL, "show", unit, "--no-pager", "--plain"]
        + [argument for property in properties for argument in ("--property", property)]
    )
    if result.returncode != 0:
        raise RuntimeError("systemctl show failed")

    values: dict[str, str] = {}
    for line in result.stdout.splitlines():
        key, separator, value = line.partition("=")
        if separator and key in properties:
            values[key] = value

    canonical_unit = values.get("Id", "")
    if canonical_unit != unit:
        raise InvalidInput("systemctl returned a different canonical unit name")

    output: UnitStatus = {"unit": unit}
    for property in properties:
        name = PROPERTY_NAMES[property]
        value: UnitStatusValue = values.get(property) or None
        if property in NUMERIC_PROPERTIES and value is not None:
            value = _optional_integer(value)
        output[name] = value
    return output


PROPERTY_NAMES = {
    "Id": "id",
    "Description": "description",
    "LoadState": "load_state",
    "ActiveState": "active_state",
    "SubState": "sub_state",
    "UnitFileState": "unit_file_state",
    "Result": "result",
    "ExecMainCode": "exec_main_code",
    "ExecMainStatus": "exec_main_status",
    "ExecMainPID": "exec_main_pid",
    "ExecMainStartTimestamp": "exec_main_start_timestamp",
    "ExecMainExitTimestamp": "exec_main_exit_timestamp",
    "ActiveEnterTimestamp": "active_enter_timestamp",
    "InactiveEnterTimestamp": "inactive_enter_timestamp",
    "NRestarts": "n_restarts",
    "InvocationID": "invocation_id",
}

NUMERIC_PROPERTIES = {
    "ExecMainCode",
    "ExecMainStatus",
    "ExecMainPID",
    "NRestarts",
}


def _journal_entry(raw: str) -> JournalEntry | None:
    try:
        decoded = cast(object, json.loads(raw))
    except json.JSONDecodeError:
        return None
    if not isinstance(decoded, dict):
        return None
    # JSON object keys are always strings; only the values remain dynamic.
    value = cast(JsonObject, decoded)

    timestamp = None
    microseconds = _optional_integer(value.get("__REALTIME_TIMESTAMP", ""))
    if microseconds is not None:
        try:
            timestamp = (
                dt.datetime.fromtimestamp(microseconds / 1_000_000, tz=dt.UTC)
                .isoformat(timespec="milliseconds")
                .replace("+00:00", "Z")
            )
        except (ValueError, OverflowError):
            timestamp = None

    message = value.get("MESSAGE")
    if not isinstance(message, str):
        message = ""
    message, redactions = redact_text(message)
    message, was_truncated = _truncate_bytes(message, JOURNAL_MESSAGE_MAX_BYTES)

    return {
        "timestamp": timestamp,
        "priority": _optional_integer(value.get("PRIORITY", "")),
        "identifier": _first_text(value, ("SYSLOG_IDENTIFIER", "_COMM")),
        "pid": _optional_integer(value.get("_PID", "")),
        "unit": _first_text(value, ("_SYSTEMD_UNIT", "UNIT")),
        "message": message,
        "message_truncated": was_truncated,
        "redactions": redactions,
    }


def _limit_journal_entries(
    entries: list[JournalEntry],
) -> tuple[list[JournalEntry], int]:
    selected: list[JournalEntry] = []
    used = 0
    omitted = 0
    for entry in reversed(entries):
        size = len(
            json.dumps(entry, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        )
        if selected and used + size > JOURNAL_OUTPUT_MAX_BYTES:
            omitted += 1
            continue
        if size > JOURNAL_OUTPUT_MAX_BYTES:
            omitted += 1
            continue
        selected.append(entry)
        used += size
    selected.reverse()
    return selected, omitted


def journal_result(
    raw_lines: list[str], unit: str, requested_lines: int
) -> JournalResult:
    entries: list[JournalEntry] = []
    parse_errors = 0
    for raw in raw_lines:
        entry = _journal_entry(raw)
        if entry is None:
            parse_errors += 1
        else:
            entries.append(entry)

    selected, omitted = _limit_journal_entries(entries)
    redactions = sum(entry["redactions"] for entry in selected)
    truncated_messages = sum(1 for entry in selected if entry["message_truncated"])
    return {
        "unit": unit,
        "boot": "current",
        "entries": selected,
        "requested": requested_lines,
        "returned": len(selected),
        "available": len(entries),
        "omitted": omitted,
        "parse_errors": parse_errors,
        "redactions": redactions,
        "truncated_messages": truncated_messages,
        "output_byte_limit": JOURNAL_OUTPUT_MAX_BYTES,
        "sensitive_hint": True,
    }


def unit_journal(unit: str, lines: int = 80, priority: int = 7) -> JournalResult:
    unit = validate_unit(unit)
    lines = validate_limit(lines, JOURNAL_MAX_LINES, 80)
    priority = validate_priority(priority)
    result = _run(
        [
            JOURNALCTL,
            "--boot",
            f"--unit={unit}",
            f"--lines={lines}",
            f"--priority={priority}",
            "--no-pager",
            "--output=json",
        ]
    )
    if result.returncode != 0:
        raise RuntimeError("journalctl failed")
    return journal_result(result.stdout.splitlines(), unit, lines)


def nixos_generations(limit: int = 20) -> GenerationResult:
    limit = validate_limit(limit, GENERATION_MAX_LIMIT, 20)
    generations: list[GenerationEntry] = []
    for link in glob.glob(str(SYSTEM_PROFILE.parent / "system-*-link")):
        match = GENERATION_RE.fullmatch(os.path.basename(link))
        if not match:
            continue
        try:
            stat = os.lstat(link)
        except OSError:
            continue
        generations.append(
            {
                "generation": int(match.group(1)),
                "path": os.path.realpath(link),
                "modified_at": dt.datetime.fromtimestamp(stat.st_mtime, tz=dt.UTC)
                .isoformat(timespec="milliseconds")
                .replace("+00:00", "Z"),
                "current": False,
            }
        )

    generations.sort(key=lambda item: item["generation"], reverse=True)
    current = _profile_generation()
    for item in generations:
        item["current"] = item["generation"] == current
    return {
        "current_generation": current,
        "returned": min(len(generations), limit),
        "generations": generations[:limit],
    }
