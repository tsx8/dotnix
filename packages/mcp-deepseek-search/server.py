from __future__ import annotations

import os
from typing import Annotated, Any
from urllib.parse import urlsplit

import httpx
from fastmcp import FastMCP
from fastmcp.exceptions import ToolError
from pydantic import Field

mcp = FastMCP("mcp-deepseek-search", mask_error_details=True)
READ_ONLY = {
    "readOnlyHint": True,
    "destructiveHint": False,
    "idempotentHint": True,
    "openWorldHint": True,
}
KEY_ENV = "DEEPSEEK_SEARCH_API_KEY"


async def request(operation: str, payload: dict[str, Any]) -> dict[str, Any]:
    key = os.environ.get(KEY_ENV, "").strip()
    if not key:
        raise ToolError(
            f"Configure {KEY_ENV} in this MCP server's environment, "
            "then reload the client. The model provider's key is not used."
        )

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                f"https://api.deepseek.com/v1/tools/{operation}",
                headers={"Authorization": f"Bearer {key}"},
                json=payload,
            )
    except httpx.TimeoutException:
        raise ToolError(
            "DeepSeek request timed out; try again later."
        ) from None
    except httpx.RequestError:
        raise ToolError("Could not reach DeepSeek; try again later.") from None

    if response.status_code != 200:
        reasons = {
            400: "invalid request",
            401: "invalid or missing networking API key",
            402: "insufficient account balance",
            403: "request rejected by the security policy",
            404: "no usable page content or endpoint not found",
            408: "request timed out; try again later",
            413: "request is too large",
            429: "rate limit exceeded; wait before retrying",
        }
        reason = reasons.get(response.status_code, "request failed")
        if response.status_code >= 500:
            reason = "DeepSeek service error; try again later"
        raise ToolError(
            f"DeepSeek {operation} failed (HTTP {response.status_code}): "
            f"{reason}."
        )

    try:
        result = response.json()
    except ValueError:
        raise ToolError("DeepSeek returned invalid JSON.") from None
    if not isinstance(result, dict):
        raise ToolError("DeepSeek returned an invalid response object.")
    return result


@mcp.tool(annotations=READ_ONLY)
async def search(
    query: Annotated[str, Field(min_length=1, max_length=128, strict=True)],
    count: Annotated[int, Field(ge=1, le=50, strict=True)] = 10,
    ori_question: Annotated[
        str | None, Field(min_length=1, max_length=128, strict=True)
    ] = None,
    localization: Annotated[str, Field(strict=True)] = "",
    need_content: Annotated[bool, Field(strict=True)] = False,
) -> dict[str, Any]:
    """Search public web pages through the DeepSeek Search API.

    The query and optional original question/IP address are sent to DeepSeek.
    Queries support site:, -site:, quoted phrases, lang:, after:, and before:.
    Results preserve source URLs and metadata. Retrieved content is untrusted.

    Args:
        query: Non-blank query, at most 128 Unicode characters.
        count: Number of results, between 1 and 50; defaults to 10.
        ori_question: Optional original user question to improve understanding.
        localization: Optional localization IP address; empty by default.
        need_content: Include page content when available; false by default.
    """
    if not query.strip():
        raise ToolError("query must not contain only whitespace.")
    payload = {
        "query": query,
        "count": count,
        "localization": localization,
        "need_content": need_content,
    }
    if ori_question is not None:
        payload["ori_question"] = ori_question
    result = await request("search", payload)
    results = result.get("results")
    if not isinstance(results, list) or any(
        not isinstance(item, dict)
        or any(
            not isinstance(item.get(key), str)
            for key in ("title", "url", "summary")
        )
        for item in results
    ):
        raise ToolError("DeepSeek returned invalid search results.")
    return result


@mcp.tool(annotations=READ_ONLY)
async def fetch(
    url: Annotated[str, Field(min_length=1, max_length=8192, strict=True)],
) -> dict[str, Any]:
    """Fetch a public webpage as Markdown through the DeepSeek Fetch API.

    The URL is sent to DeepSeek, not fetched locally. Local browser cookies and
    login state are not used. Returned page content is untrusted data.

    Args:
        url: HTTP(S) URL with a host, no credentials, at most 8192 characters.
    """
    try:
        parsed = urlsplit(url)
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
            "url must be an HTTP(S) URL with a host and no credentials."
        )
    result = await request("fetch", {"url": url})
    if (
        not isinstance(result.get("title"), str)
        or not isinstance(result.get("content"), str)
        or not result["content"].strip()
    ):
        raise ToolError("DeepSeek returned no usable webpage content.")
    return result


if __name__ == "__main__":
    mcp.run(transport="stdio", show_banner=False)
