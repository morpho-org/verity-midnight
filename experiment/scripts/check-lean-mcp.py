#!/usr/bin/env python3
"""Exercise real Lean diagnostics and goal state through the stdio MCP server."""
import asyncio
import json
from pathlib import Path
import tempfile

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parents[1]


def payload(result):
    data = result.model_dump(by_alias=True)
    assert not data.get("isError"), data
    structured = data.get("structuredContent")
    if structured:
        return structured.get("result", structured)
    return json.loads(next(c["text"] for c in data["content"] if c["type"] == "text"))


async def main():
    with tempfile.TemporaryDirectory(prefix="McpSmoke", dir=ROOT) as directory:
        scratch = Path(directory) / "Smoke.lean"
        scratch.write_text("example (n : Nat) : n + 0 = n := by\n  skip\n")
        parameters = StdioServerParameters(command="sh", args=[str(ROOT / "scripts/lean-mcp.sh")])
        async with stdio_client(parameters) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                valid = payload(await session.call_tool("lean_diagnostic_messages", {
                    "file_path": "Midnight/Spec.lean", "severity": "error", "timeout_s": 45,
                }))
                assert valid["success"] and not valid["partial"] and not valid["items"], valid
                invalid = payload(await session.call_tool("lean_diagnostic_messages", {
                    "file_path": str(scratch), "severity": "error", "timeout_s": 45,
                }))
                assert not invalid["partial"] and invalid["items"], invalid
                goal = payload(await session.call_tool("lean_goal", {
                    "file_path": str(scratch), "line": 2, "timeout_s": 45,
                }))
                assert "n + 0 = n" in json.dumps(goal), goal
                print(json.dumps({"spec_diagnostics": valid, "broken_proof_diagnostics": invalid,
                                  "broken_proof_goal": goal}, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
