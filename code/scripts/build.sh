#!/usr/bin/env bash
# Build a b-parasite nRF Connect SDK sample.
# Assumes west + cmake + ninja + the arm-zephyr-eabi toolchain are on PATH
# (e.g. inside ghcr.io/zephyrproject-rtos/ci).
#
# Workspace topology: T1. The workspace top dir is code/, with code/prstlib/
# acting as the manifest repo and a Zephyr module (auto-discovered).
# Sample apps live in code/samples/<name>/. west
# clones (nrf/, zephyr/, ncs-zigbee/, …) land in code/ and are gitignored.
set -euo pipefail

usage() {
  cat >&2 <<EOF
usage: $(basename "$0") <sample> [soc] [revision]
  sample    blinky | input | ble | soil-read-loop | zigbee
  soc       nrf52840 (default) | nrf52833
  revision  2.0.0 (default) | 1.2.0 | 1.1.0 | 1.0.0

env:
  CMAKE_EXTRA   extra -D… flags appended to west build
EOF
  exit 1
}

SAMPLE="${1:-}"
SOC="${2:-nrf52840}"
REV="${3:-2.0.0}"
CMAKE_EXTRA="${CMAKE_EXTRA:-}"

[ -z "$SAMPLE" ] && usage

case "$SAMPLE" in
  blinky|input|ble|soil-read-loop|zigbee) ;;
  *)
    echo "unknown sample: $SAMPLE" >&2
    usage ;;
esac

# The workspace top dir is the parent of this script's dir (code/scripts/).
WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "Running build for sample='$SAMPLE', soc='$SOC', revision='$REV' with CMAKE_EXTRA='$CMAKE_EXTRA' in workspace_dir='$WORKSPACE_DIR'…"
cd "$WORKSPACE_DIR"

if [ ! -d "samples/$SAMPLE" ]; then
  echo "sample dir not found: $WORKSPACE_DIR/samples/$SAMPLE" >&2
  exit 1
fi

echo "Building sample '$SAMPLE' for SOC '$SOC' revision '$REV' with CMAKE_EXTRA='$CMAKE_EXTRA'…"
echo workspace_dir="$WORKSPACE_DIR"
if [ -n "${ZEPHYR_BASE:-}" ]; then
  echo "warning: ZEPHYR_BASE is set to '$ZEPHYR_BASE', west may not find the Zephyr module in the manifest"
else
  echo "ZEPHYR_BASE is not set, west should find the Zephyr module in the manifest"
fi

if [ ! -d .west ]; then
  echo "Initializing west workspace and installing Python dependencies…"
  west init -l prstlib
  west update --narrow --fetch-opt=--depth=1
  pip install \
    -r zephyr/scripts/requirements.txt \
    -r nrf/scripts/requirements.txt
else
  echo "West workspace already initialized, skipping west init/update and Python dependencies installation"
fi

west build --pristine \
  --build-dir "samples/$SAMPLE/build_${SOC}_${REV}" \
  --board "bparasite@${REV}/${SOC}" \
  "samples/$SAMPLE" -- \
  $CMAKE_EXTRA
