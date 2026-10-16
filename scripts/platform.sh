# Sourced. Sets PLATFORM, the Docker platform of the agent image, to the host's
# native Linux platform unless it is already set: linux/arm64 on Apple Silicon
# or ARM servers, linux/amd64 on Intel/AMD. Everything in the image runs
# natively on both, except solc (see scripts/install-solc.py).
if [[ -z "${PLATFORM:-}" ]]; then
  case "$(uname -m)" in
    arm64|aarch64) PLATFORM=linux/arm64 ;;
    x86_64|amd64) PLATFORM=linux/amd64 ;;
    *) echo "Unknown host architecture $(uname -m); set PLATFORM=linux/amd64 or linux/arm64" >&2
       exit 2 ;;
  esac
fi
export PLATFORM
