#!/usr/bin/env bash
# Thin wrapper: runs scripts/build.sh inside the Zephyr CI container image,
# the same image used by GitHub Actions. Works with either Docker or Podman
# — the CLI surface used here (`run --rm -v -w -e`) is identical between
# them. The first run clones the NCS workspace (sdk-nrf, zephyr, modules, …)
# into code/; subsequent runs reuse it.
#
# All arguments are forwarded verbatim to scripts/build.sh, so
#   ./scripts/build-with-docker.sh blinky nrf52840 2.0.0ry1 --uf2
# produces a zephyr.uf2 next to zephyr.hex in the build dir.
#
# Override the runtime with B_PARASITE_CONTAINER_RUNTIME=docker (or podman,
# or an absolute path) if auto-detection picks the wrong one.
set -euo pipefail

# Pick a container runtime: explicit env override → podman → docker.
# Podman is preferred when both are installed because that's the
# rootless-by-default option that matches the dev setup on this repo;
# users who specifically want Docker can set B_PARASITE_CONTAINER_RUNTIME.
RUNTIME="${B_PARASITE_CONTAINER_RUNTIME:-}"
if [ -z "$RUNTIME" ]; then
  if command -v podman >/dev/null 2>&1; then
    RUNTIME=podman
  elif command -v docker >/dev/null 2>&1; then
    RUNTIME=docker
  else
    echo "ERROR: neither 'podman' nor 'docker' found on PATH." >&2
    echo "Install one of them, or set B_PARASITE_CONTAINER_RUNTIME to a" >&2
    echo "binary that accepts the same 'run --rm -v … -w … -e …' flags." >&2
    exit 1
  fi
fi

if [[ "$(uname -m)" == "arm64" ]]; then
  echo "Running on arm64 container image"
  IMAGE="${B_PARASITE_DOCKER_IMAGE:-ghcr.io/zephyrproject-rtos/ci:v0.28.8-arm64}"
else
  echo "Running on amd64 container image"
  IMAGE="${B_PARASITE_DOCKER_IMAGE:-ghcr.io/zephyrproject-rtos/ci:v0.28.8}"
fi

# Mount code/ as /workspace inside the container — that's the west workspace
# top dir, all the script needs.
WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Running build via '$RUNTIME' on image '$IMAGE' with workspace_dir='$WORKSPACE_DIR'…"

exec "$RUNTIME" run --rm \
  -v "$WORKSPACE_DIR":/workspace \
  -w /workspace \
  -e CMAKE_EXTRA="${CMAKE_EXTRA:-}" \
  "$IMAGE" \
  scripts/build.sh "$@"
