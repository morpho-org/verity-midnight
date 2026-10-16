#!/usr/bin/env python3
"""Install the pinned solc that Verity's `solidity_import` accepts, on any host.

  install-solc.py VERITY_SETUP_SCRIPT DEST

The importer only accepts the official linux-amd64 and macOS binaries (checked
by SHA-256), and there is no official linux-arm64 build. So the agent image
always uses the linux-amd64 binary, also on linux/arm64, where it runs under
the host's amd64 emulation (Rosetta in Docker Desktop on Apple Silicon; on an
ARM Linux server, install it with
`docker run --privileged --rm tonistiigi/binfmt --install amd64`).
Verity's own setup script refuses to install on linux/arm64, so this reuses
its pins and download code with the platform fixed to linux-amd64.
"""
from pathlib import Path
import runpy
import subprocess
import sys

VERSION = "0.8.34"
PLATFORM = "linux-amd64"


def main() -> int:
    setup = runpy.run_path(sys.argv[1])
    dest = Path(sys.argv[2])
    expected = setup["RELEASES"][VERSION]["sha256"][PLATFORM]
    if dest.exists() and setup["file_sha256"](dest) == expected:
        print(f"solc {VERSION} ({PLATFORM}) already installed at {dest}")
    else:
        setup["install"](VERSION, PLATFORM, dest)
    try:
        banner = subprocess.run([str(dest), "--version"], capture_output=True, text=True,
                                check=True).stdout.strip().splitlines()[-1]
    except (OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"Cannot run the linux-amd64 solc on this platform ({error}). On an ARM "
                 "Linux host, enable amd64 emulation: "
                 "docker run --privileged --rm tonistiigi/binfmt --install amd64")
    print(f"solc runs: {banner}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
