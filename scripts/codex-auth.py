#!/usr/bin/env python3
"""Validate or copy a ChatGPT login cache without printing its credentials."""

import json
from pathlib import Path
import sys


def main() -> None:
    source = Path(sys.argv[1])
    try:
        auth_bytes = source.read_bytes()
        auth = json.loads(auth_bytes)
    except (OSError, ValueError):
        sys.exit("Cannot read ChatGPT login cache. Run codex login first, or set CODEX_AUTH_FILE.")
    if not isinstance(auth, dict):
        sys.exit("Invalid ChatGPT login cache. Run codex login first.")
    if auth.get("auth_mode") != "chatgpt" or not auth.get("tokens"):
        sys.exit("The login cache is not a ChatGPT login. Run codex login first.")
    for destination in sys.argv[2:]:
        directory = Path(destination)
        directory.mkdir(parents=True, exist_ok=True)
        target = directory / "auth.json"
        # Set permissions before writing access tokens.
        with target.open("wb") as output:
            target.chmod(0o600)
            output.write(auth_bytes)
        config = directory / "config.toml"
        config_text = config.read_text() if config.exists() else ""
        # These are top-level settings, so place them before any MCP tables.
        config.write_text('forced_login_method = "chatgpt"\n'
                          'cli_auth_credentials_store = "file"\n' + config_text)
    print("ChatGPT login cache validated" if len(sys.argv) == 2 else "ChatGPT login installed in isolated agent homes")


if __name__ == "__main__":
    main()
