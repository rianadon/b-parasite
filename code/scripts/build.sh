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
  revision  2.0.0 (default) | 1.2.0 | 1.1.0

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
cd "$WORKSPACE_DIR"

if [ ! -d "samples/$SAMPLE" ]; then
  echo "sample dir not found: $WORKSPACE_DIR/samples/$SAMPLE" >&2
  exit 1
fi

# The Zephyr CI image bakes in ZEPHYR_BASE=/workspace/zephyr for its canonical
# layout. Our workspace topdir is code/, so let west rediscover zephyr from
# the manifest by clearing the env var.
# unset ZEPHYR_BASE

# if [ ! -d .west ]; then
west init -l prstlib
west update -o=--depth=1 -n
pip install \
  -r zephyr/scripts/requirements.txt \
  -r nrf/scripts/requirements.txt
# fi

west build --pristine \
  --build-dir "samples/$SAMPLE/build_${SOC}_${REV}" \
  --board "bparasite@${REV}/${SOC}" \
  "samples/$SAMPLE" -- \
  $CMAKE_EXTRA
