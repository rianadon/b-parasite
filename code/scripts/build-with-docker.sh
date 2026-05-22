#!/usr/bin/env bash
# Thin wrapper: runs scripts/build.sh inside the Zephyr CI docker image,
# the same image used by GitHub Actions. The first run clones the NCS
# workspace (sdk-nrf, zephyr, modules, …) into code/; subsequent runs reuse it.
set -euo pipefail

IMAGE="${B_PARASITE_DOCKER_IMAGE:-ghcr.io/zephyrproject-rtos/ci:v0.28.8}"

# Mount code/ as /workspace inside the container — that's the west workspace
# top dir, all the script needs.
WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

exec docker run --rm \
  -v "$WORKSPACE_DIR":/workspace \
  -w /workspace \
  -e CMAKE_EXTRA="${CMAKE_EXTRA:-}" \
  "$IMAGE" \
  scripts/build.sh "$@"

