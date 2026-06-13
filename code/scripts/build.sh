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
usage: $(basename "$0") <sample> [soc] [revision] [--uf2]
  sample    blinky | input | ble | soil-read-loop | zigbee
  soc       nrf52840 (default) | nrf52833
  revision  2.0.0 (default) | 1.2.0 | 1.1.0 | 1.0.0 | 2.0.0ry1
  --uf2     also emit a .uf2 next to zephyr.hex, targeting the Adafruit
            nRF52840 UF2 bootloader (family 0xADA52840, app at 0x26000).
            Implies CONFIG_USE_DT_CODE_PARTITION=y and disables NCS's
            Partition Manager so the linker honors the slot0 offset.

env:
  CMAKE_EXTRA   extra -D… flags appended to west build
EOF
  exit 1
}

UF2=0
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --uf2) UF2=1 ;;
    -h|--help) usage ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

SAMPLE="${POSITIONAL[0]:-}"
SOC="${POSITIONAL[1]:-nrf52840}"
REV="${POSITIONAL[2]:-2.0.0}"
CMAKE_EXTRA="${CMAKE_EXTRA:-}"

[ -z "$SAMPLE" ] && usage

case "$SAMPLE" in
  blinky|input|ble|soil-read-loop|zigbee) ;;
  *)
    echo "unknown sample: $SAMPLE" >&2
    usage ;;
esac

if [ "$UF2" = "1" ]; then
  if [ "$SOC" != "nrf52840" ]; then
    echo "--uf2 is only wired up for nrf52840 (family 0xADA52840); got '$SOC'" >&2
    exit 1
  fi
  # Force the linker to use slot0_partition's address from devicetree (0x26000
  # on revisions with the UF2 layout), and turn off NCS's Partition Manager so
  # it doesn't put the image back at 0x0.
  CMAKE_EXTRA="$CMAKE_EXTRA -DCONFIG_USE_DT_CODE_PARTITION=y -DSB_CONFIG_PARTITION_MANAGER=n -DCONFIG_PARTITION_MANAGER_ENABLED=n"
fi

# The workspace top dir is the parent of this script's dir (code/scripts/).
WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "Running build for sample='$SAMPLE', soc='$SOC', revision='$REV', uf2='$UF2' with CMAKE_EXTRA='$CMAKE_EXTRA' in workspace_dir='$WORKSPACE_DIR'…"
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

BUILD_DIR="samples/$SAMPLE/build_${SOC}_${REV}"
west build --pristine \
  --build-dir "$BUILD_DIR" \
  --board "bparasite@${REV}/${SOC}" \
  "samples/$SAMPLE" -- \
  $CMAKE_EXTRA

if [ "$UF2" = "1" ]; then
  # zephyr.hex is the post-build artifact; convert with the Adafruit family ID.
  # Output lands next to it so users see a sibling zephyr.uf2.
  HEX="$BUILD_DIR/$SAMPLE/zephyr/zephyr.hex"
  UF2_OUT="$BUILD_DIR/$SAMPLE/zephyr/zephyr.uf2"
  if [ ! -f "$HEX" ]; then
    echo "expected hex not found: $HEX" >&2
    exit 1
  fi
  echo "Generating UF2 → $UF2_OUT"
  python3 scripts/uf2conv.py -f 0xADA52840 -c -o "$UF2_OUT" "$HEX"
fi
