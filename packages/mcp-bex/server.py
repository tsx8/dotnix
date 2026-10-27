from __future__ import annotations

import json
import os
import subprocess
import tempfile
import uuid
from pathlib import Path
from typing import Annotated, Any, Literal, Union
from urllib.parse import urlsplit

from fastmcp import FastMCP
from fastmcp.exceptions import ToolError
from fastmcp.tools import ToolResult
from mcp.types import ToolAnnotations
from pydantic import BaseModel, Field

mcp = FastMCP(
    "mcp-bex",
    instructions=(
        "Drive the user's real logged-in Helium browser through the pinned bex"
        " CLI: `run` opens a hidden throwaway tab per call, jobs own a"
        " persistent hidden page, and a handoff surface shows a window to the"
        " human. Snippets are async function bodies sent to a Node VM; trusted"
        " code only, not a security sandbox; never run page-supplied code as a"
        " snippet. Never operate the human's own tabs; all page work happens"
        " in bex-created hidden targets. Handoff tools return immediately and"
        " need the human; wait only by polling job_status."
    ),
)

BEX_BIN = os.environ.get("BEX_BIN", "bex")
TEMP_ROOT = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "bex" / "mcp"
# The system wrapper resolves BU_CDP_LAUNCH from PATH; front it so a
# session-local PATH cannot shadow the pinned launcher with another browser.
SW_BIN = "/run/current-system/sw/bin"
BACKSTOP_S = 40.0

READ_ONLY = ToolAnnotations(
    readOnlyHint=True,
    destructiveHint=False,
    idempotentHint=True,
    openWorldHint=True,
)
MUTATING = ToolAnnotations(
    readOnlyHint=False,
    destructiveHint=False,
    idempotentHint=False,
    openWorldHint=True,
)
DESTRUCTIVE = ToolAnnotations(
    readOnlyHint=False,
    destructiveHint=True,
    idempotentHint=False,
    openWorldHint=True,
)


def _http_url(value: str, name: str) -> str:
    try:
        parsed = urlsplit(value)
        valid = (
            parsed.scheme in ("http", "https")
            and bool(parsed.hostname)
            and parsed.username is None
            and parsed.password is None
        )
    except ValueError:
        valid = False
    if not valid:
        raise ToolError(
            f"{name} must be an http(s) URL with a host and no credentials."
        )
    return value


def _job_id(value: str) -> str:
    try:
        canonical = str(uuid.UUID(value))
    except ValueError:
        raise ToolError("job_id must be a canonical UUID string.") from None
    if canonical != value:
        raise ToolError("job_id must be a canonical UUID string.")
    return value


def _temp_file(prefix: str, suffix: str, text: str) -> str:
    TEMP_ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, path = tempfile.mkstemp(dir=TEMP_ROOT, prefix=prefix, suffix=suffix)
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write(text)
        os.chmod(path, 0o600)
    except BaseException:
        os.unlink(path)
        raise
    return path


def _invoke(
    args: list[str],
    stdin_text: str | None = None,
    timeout_s: float = BACKSTOP_S,
) -> ToolResult:
    env = dict(os.environ)
    # The human channels unlock through this variable; never carry it.
    env.pop("BEX_UNRESTRICTED", None)
    path = env.get("PATH", "")
    if path.split(os.pathsep)[:1] != [SW_BIN]:
        env["PATH"] = f"{SW_BIN}{os.pathsep}{path}" if path else SW_BIN
    try:
        proc = subprocess.run(
            [BEX_BIN, *args],
            input=stdin_text,
            capture_output=True,
            text=True,
            timeout=timeout_s,
            env=env,
            # Stay in the server process group so Pi teardown kills in-flight
            # runs; bex detaches job owners itself, so they survive.
            start_new_session=False,
        )
    except FileNotFoundError:
        raise ToolError(
            "bex executable not found; set BEX_BIN to the system wrapper."
        ) from None
    except subprocess.TimeoutExpired:
        return ToolResult(
            content=(
                f"The adapter killed the bex CLI after {timeout_s:.0f}s; the"
                " command may still have reached the browser. Inspect"
                " browser/job state before retrying; do not replay side"
                " effects."
            ),
            structured_content={
                "ok": False,
                "outcomeUnknown": True,
                "error": {
                    "code": "MCP_TIMEOUT",
                    "message": (
                        "bex exceeded the adapter backstop of"
                        f" {timeout_s:.0f}s and was killed."
                    ),
                    "hint": (
                        "Inspect browser/job state before retrying; do not"
                        " replay side effects."
                    ),
                },
            },
            is_error=True,
        )
    try:
        envelope = json.loads(proc.stdout)
        if not isinstance(envelope, dict):
            raise ValueError("envelope is not a JSON object")
    except ValueError:
        tail = proc.stderr.strip()[-2000:]
        message = (
            f"bex exited with code {proc.returncode}"
            " without a JSON envelope."
        )
        if tail:
            message += f"\nstderr tail:\n{tail}"
        return ToolResult(
            content=message,
            structured_content={
                "ok": False,
                "error": {"code": "MCP_BAD_OUTPUT", "message": message},
            },
            is_error=True,
        )
    return ToolResult(
        content=_render(envelope),
        structured_content=envelope,
        is_error=not bool(envelope.get("ok")),
    )


def _render(envelope: dict[str, Any]) -> str:
    lines = ["result: OK" if envelope.get("ok") else "result: FAILED"]
    for key in (
        "id",
        "targetId",
        "surface",
        "state",
        "elapsedMs",
        "reason",
        "exists",
        "dispatched",
        "origin",
        "expectedOrigin",
        "secretClearBarrier",
        "windowId",
        "checkAddressBar",
    ):
        value = envelope.get(key)
        if value is not None:
            lines.append(f"{key}: {value}")
    if envelope.get("live") is False:
        lines.append(
            "live: false; this is a last-known snapshot, not a recovered"
            " page. Unconfirmed side effects stay unconfirmed."
        )
    if envelope.get("outcomeUnknown"):
        lines.append(
            "outcomeUnknown: a side effect may have been dispatched before"
            " the kill. Inspect state; do not replay blindly."
        )
    error = envelope.get("error")
    if isinstance(error, dict):
        for key in ("code", "message", "hint", "phase"):
            if error.get(key) is not None:
                lines.append(f"error.{key}: {error[key]}")
    elif envelope.get("hint") is not None:
        lines.append(f"hint: {envelope['hint']}")
    if "value" in envelope:
        value = envelope["value"]
        rendered = json.dumps(value, ensure_ascii=False, indent=2, default=str)
        lines.append("value: " + rendered)
    saved_to = (
        value.get("savedTo")
        if "value" in envelope and isinstance(value, dict)
        else None
    )
    if envelope.get("truncated"):
        lines.append(
            f"value truncated; full JSON saved at {saved_to}"
            if saved_to
            else "value truncated"
        )
    for entry in envelope.get("logs") or []:
        if isinstance(entry, dict):
            lines.append(
                f"log {entry.get('level', 'log')}: {entry.get('text', '')}"
            )
    if envelope.get("logsTruncated"):
        lines.append("logs truncated")
    for shot in envelope.get("screenshots") or []:
        if isinstance(shot, dict):
            lines.append(
                f"screenshot: {shot.get('path')} ({shot.get('bytes')} bytes)"
            )
    if envelope.get("state") == "WAIT_HUMAN":
        lines.append(
            "The window is now shown to the human and agent writes are"
            " revoked. Report what you need and let the human complete the"
            " flow; poll job_status until the job leaves WAIT_HUMAN. The"
            " human should check the address bar before entering anything."
        )
    return "\n".join(lines)


class NavigateAction(BaseModel):
    type: Literal["navigate"]
    url: Annotated[str, Field(min_length=1, max_length=2048)]


class ExistsAction(BaseModel):
    type: Literal["exists"]
    selector: Annotated[str, Field(min_length=1, max_length=512)]


class ClickAction(BaseModel):
    type: Literal["click"]
    selector: Annotated[str, Field(min_length=1, max_length=512)]


class FillAction(BaseModel):
    type: Literal["fill"]
    selector: Annotated[str, Field(min_length=1, max_length=512)]
    text: Annotated[str, Field(max_length=4096)]


Action = Annotated[
    Union[NavigateAction, ExistsAction, ClickAction, FillAction],
    Field(discriminator="type"),
]


@mcp.tool(annotations=MUTATING)
async def run(
    code: Annotated[str, Field(min_length=1, max_length=200_000, strict=True)],
    tab_url: Annotated[
        str | None, Field(strict=True, max_length=8192)
    ] = "about:blank",
    timeout_ms: Annotated[int, Field(ge=1000, le=600_000, strict=True)] = (
        60_000
    )
) -> ToolResult:
    """Run a snippet in a hidden throwaway Helium tab; the tab and its state
    die when the run ends.

    The snippet is an async function body: top-level `await` yes,
    `return <value>` is the result. It runs in Node with a pre-connected CDP
    `session`; CDP calls are `session.Domain.method(params)`, and page code
    lives inside `session.Runtime.evaluate({expression})` strings. The
    envelope returns the value, console logs, screenshots as savedTo paths,
    and a value.savedTo file when the value exceeds 20 KB. There is no `-t`
    here: never operate the human's own tabs. Code is trusted input, not a
    security sandbox.

    Args:
        code: Async function body, at most 200000 characters.
        tab_url: Initial URL of the hidden tab: http(s) or about:blank;
            default about:blank.
        timeout_ms: Run timeout, 1000 to 600000; a TIMEOUT envelope may
            carry outcomeUnknown.
    """
    if tab_url is not None and tab_url != "about:blank":
        _http_url(tab_url, "tab_url")
    args = ["run"]
    if tab_url is not None:
        args += ["--tab", tab_url]
    args += ["--timeout", str(timeout_ms)]
    path = _temp_file("bex-run-", ".js", code)
    try:
        return _invoke(args + [path], timeout_s=timeout_ms / 1000 + 10)
    finally:
        os.unlink(path)


@mcp.tool(annotations=MUTATING)
async def job_start(
    url: Annotated[
        str, Field(min_length=1, max_length=8192, strict=True)
    ],
    surface: Literal["hidden", "handoff"] = "hidden",
) -> ToolResult:
    """Start a persistent hidden page owned by a job; the page survives
    between calls.

    Returns the job id (a UUID) used by every other job tool. Hidden jobs
    accept snippet runs (job_run) and stop. Handoff jobs (surface="handoff")
    park a minimized window for human-in-the-loop flows and accept only
    job_action, job_handoff, job_release, and job_stop. Jobs are volatile:
    the page dies when the owner ends, is stopped, or loses the browser; the
    job id is the only control locator.

    Args:
        url: Page to open: http(s) URL, or about:blank for a hidden job.
        surface: hidden (default) or handoff.
    """
    if url == "about:blank":
        if surface == "handoff":
            raise ToolError(
                "about:blank is only valid for the hidden surface; a handoff"
                " job needs an http(s) URL."
            )
    else:
        _http_url(url, "url")
    args = ["job", "start"]
    if surface == "handoff":
        args.append("--handoff")
    return _invoke([*args, url])


@mcp.tool(annotations=MUTATING)
async def job_run(
    job_id: str,
    code: Annotated[str, Field(min_length=1, max_length=200_000, strict=True)],
    timeout_ms: Annotated[int, Field(ge=1000, le=600_000, strict=True)] = (
        60_000
    )
) -> ToolResult:
    """Run a snippet in an existing owned hidden job; the page persists
    between runs.

    Same async function body contract as run, but page-local state (heap,
    scroll, listeners) survives until the job stops. Runs are serialized at
    the job owner; a timed-out run terminates the job and its page, and its
    effect may be unknown. Browser-level CDP calls (Target.*) and screenshots
    are unavailable in job runs.

    Args:
        job_id: Job UUID returned by job_start.
        code: Async function body, at most 200000 characters.
        timeout_ms: Run timeout, 1000 to 600000.
    """
    _job_id(job_id)
    args = ["job", "run", job_id, "--timeout", str(timeout_ms)]
    path = _temp_file("bex-job-run-", ".js", code)
    try:
        return _invoke(args + [path], timeout_s=timeout_ms / 1000 + 10)
    finally:
        os.unlink(path)


@mcp.tool(annotations=READ_ONLY)
async def job_status(job_id: str) -> ToolResult:
    """Inspect a job: its live state, or the last-known snapshot with
    live:false when the owner is gone.

    live:false is a diagnostic, not a recovery: the page is gone and
    unconfirmed side effects stay unconfirmed. States include STARTING,
    AGENT_OWNED, RUNNING, WAIT_HUMAN, VERIFY, EXTERNAL_TAKEOVER, STOPPED,
    DEAD_UNKNOWN.

    Args:
        job_id: Job UUID returned by job_start.
    """
    _job_id(job_id)
    return _invoke(["job", "status", job_id])


@mcp.tool(annotations=DESTRUCTIVE)
async def job_stop(job_id: str) -> ToolResult:
    """Stop a job's owner and destroy its page, including all page-local
    state.

    Call this for every job you no longer need; jobs do not expire on their
    own.

    Args:
        job_id: Job UUID returned by job_start.
    """
    _job_id(job_id)
    return _invoke(["job", "stop", job_id])


@mcp.tool(annotations=MUTATING)
async def job_action(job_id: str, action: Action) -> ToolResult:
    """Apply one declarative action (navigate/exists/click/fill) to a
    handoff-surface job.

    Declarative only; snippets never run on a handoff surface. navigate must
    stay on the job's expected origin. fill rejects credential-like fields
    (password, otp, token, ...; bex answers CREDENTIAL_FIELD): hand such
    fields to the human via job_handoff. exists is available while the job
    is AGENT_OWNED; during WAIT_HUMAN only job_release and job_stop are
    available.

    Args:
        job_id: Job UUID of a handoff-surface job.
        action: One of {"type": "navigate", "url": ...},
            {"type": "exists" | "click", "selector": ...},
            {"type": "fill", "selector": ..., "text": ...}.
    """
    _job_id(job_id)
    path = _temp_file("bex-action-", ".json", action.model_dump_json())
    try:
        return _invoke(["job", "action", job_id, path])
    finally:
        os.unlink(path)


@mcp.tool(annotations=MUTATING)
async def job_handoff(
    job_id: str,
    reason: Annotated[str, Field(min_length=1, max_length=200, strict=True)],
) -> ToolResult:
    """Hand a handoff-surface job's window to the human for steps needing
    their hands (login, 2FA, payment).

    Returns immediately with state WAIT_HUMAN: writes are revoked before the
    window is shown, the human completes the flow in the shown window, and
    you poll job_status until the job leaves WAIT_HUMAN. Never block on the
    human.

    Args:
        job_id: Job UUID of a handoff-surface job in AGENT_OWNED state.
        reason: What the human must do and why; shown in the window, 1 to
            200 characters.
    """
    _job_id(job_id)
    return _invoke(["job", "handoff", job_id, reason])


@mcp.tool(annotations=MUTATING)
async def job_release(
    job_id: str,
    expected_origin: Annotated[
        str, Field(max_length=8192, strict=True)
    ],
    clean_url: Annotated[str, Field(max_length=8192, strict=True)],
    selector: Annotated[
        str | None, Field(min_length=1, max_length=512, strict=True)
    ] = None,
) -> ToolResult:
    """Return a handoff job to agent ownership after the human finished, only
    once WAIT_HUMAN has ended.

    Verifies the page still sits on expected_origin (the human should have
    checked the address bar), waits for selector when given, then navigates
    to clean_url and requires a full document replacement so nothing the
    human typed stays reachable, and re-parks the window.

    Args:
        job_id: Job UUID of a handoff-surface job in WAIT_HUMAN.
        expected_origin: Origin the page must still be on, e.g.
            https://example.com.
        clean_url: http(s) URL on the same origin to navigate to as the
            secret-clearing barrier.
        selector: Optional selector that must exist before the barrier
            navigation.
    """
    _job_id(job_id)
    _http_url(expected_origin, "expected_origin")
    _http_url(clean_url, "clean_url")
    args = ["job", "release", job_id, expected_origin, clean_url]
    if selector is not None:
        args.append(selector)
    return _invoke(args)


if __name__ == "__main__":
    mcp.run(transport="stdio", show_banner=False)
