#!/usr/bin/env bash
# Thin wrapper: runs scripts/build.sh inside the Zephyr CI docker image,
# the same image used by GitHub Actions. The first run clones the NCS
# workspace (sdk-nrf, zephyr, modules, …) into code/; subsequent runs reuse it.
#
# All arguments are forwarded verbatim to scripts/build.sh, so
#   ./scripts/build-with-docker.sh blinky nrf52840 2.0.0ry1 --uf2
# produces a zephyr.uf2 next to zephyr.hex in the build dir.
set -euo pipefail

if [[ "$(uname -m)" == "arm64" ]]; then
  echo "Running on arm64 docker image"
  IMAGE="${B_PARASITE_DOCKER_IMAGE:-ghcr.io/zephyrproject-rtos/ci:v0.28.8-arm64}"
else
  echo "Running on amd64 docker image"
  IMAGE="${B_PARASITE_DOCKER_IMAGE:-ghcr.io/zephyrproject-rtos/ci:v0.28.8}"
fi

# Mount code/ as /workspace inside the container — that's the west workspace
# top dir, all the script needs.
WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Running build inside docker image '$IMAGE' with workspace_dir='$WORKSPACE_DIR'…"

exec podman run --rm \
  -v "$WORKSPACE_DIR":/workspace \
  -w /workspace \
  -e CMAKE_EXTRA="${CMAKE_EXTRA:-}" \
  "$IMAGE" \
  scripts/build.sh "$@"
