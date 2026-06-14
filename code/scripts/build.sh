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
usage: $(basename "$0") <sample> [soc] [revision] [--uf2] [--dev]
  sample    blinky | input | ble | soil-read-loop | zigbee
  soc       nrf52840 (default) | nrf52833
  revision  2.0.0 (default) | 1.2.0 | 1.1.0 | 1.0.0 | 2.0.0ry1
  --uf2     also emit a .uf2 next to zephyr.hex, targeting the Adafruit
            nRF52840 UF2 bootloader. Sets CONFIG_BUILD_OUTPUT_UF2=y so
            Zephyr's own post-build step generates zephyr.uf2 (family
            0xADA52840 is the upstream default for SOC_NRF52840_QIAA).
            Implies CONFIG_USE_DT_CODE_PARTITION=y and disables NCS's
            Partition Manager so the linker honors the slot0 offset.
  --dev     apply samples/<sample>/dev.conf and dev.overlay on top of the
            base prj.conf. Used for bring-up: enables USB CDC ACM console,
            debug logs, and a tight wake loop. Not for battery deployment.

env:
  CMAKE_EXTRA   extra -D… flags appended to west build
EOF
  exit 1
}

UF2=0
DEV=0
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --uf2) UF2=1 ;;
    --dev) DEV=1 ;;
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
  # on revisions with the UF2 layout).
  CMAKE_EXTRA="$CMAKE_EXTRA -DCONFIG_USE_DT_CODE_PARTITION=y"
  # Have Zephyr's own build system emit zephyr.uf2 alongside zephyr.hex.
  # Family ID 0xADA52840 is the upstream default for SOC_NRF52840_QIAA,
  # and the base address comes from CONFIG_FLASH_LOAD_OFFSET (which
  # USE_DT_CODE_PARTITION points at slot0 = 0x26000).
  CMAKE_EXTRA="$CMAKE_EXTRA -DCONFIG_BUILD_OUTPUT_UF2=y"
  # Auto-detect whether the sample needs Partition Manager: if it ships
  # pm_static.yml it's committed to the PM regime (zigbee needs this
  # because zb_nrf_nvram.c hard-includes pm_config.h). Otherwise turn
  # PM off so the linker honours the DT slot0 offset instead of letting
  # PM default the app to 0x0.
  if [ ! -f "samples/$SAMPLE/pm_static.yml" ]; then
    CMAKE_EXTRA="$CMAKE_EXTRA -DSB_CONFIG_PARTITION_MANAGER=n -DCONFIG_PARTITION_MANAGER_ENABLED=n"
  fi
fi

if [ "$DEV" = "1" ]; then
  # dev.conf / dev.overlay live at samples/<sample>/. EXTRA_CONF_FILE and
  # EXTRA_DTC_OVERLAY_FILE need the sysbuild image-name prefix; sysbuild
  # normalizes hyphens to underscores for the variable name.
  IMAGE_NAME="${SAMPLE//-/_}"
  DEV_CONF="samples/$SAMPLE/dev.conf"
  DEV_OVERLAY="samples/$SAMPLE/dev.overlay"
  if [ ! -f "$DEV_CONF" ]; then
    echo "--dev requested but $DEV_CONF not found" >&2
    exit 1
  fi
  CMAKE_EXTRA="$CMAKE_EXTRA -D${IMAGE_NAME}_EXTRA_CONF_FILE=dev.conf"
  if [ -f "$DEV_OVERLAY" ]; then
    CMAKE_EXTRA="$CMAKE_EXTRA -D${IMAGE_NAME}_EXTRA_DTC_OVERLAY_FILE=dev.overlay"
  fi
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

# Dev and prod get separate build dirs and UF2 filenames so a user can
# rebuild one without invalidating or overwriting the other.
if [ "$DEV" = "1" ]; then
  BUILD_DIR="samples/$SAMPLE/build_${SOC}_${REV}_dev"
  UF2_NAME="zephyr-dev.uf2"
else
  BUILD_DIR="samples/$SAMPLE/build_${SOC}_${REV}"
  UF2_NAME="zephyr.uf2"
fi
west build --pristine \
  --build-dir "$BUILD_DIR" \
  --board "bparasite@${REV}/${SOC}" \
  "samples/$SAMPLE" -- \
  $CMAKE_EXTRA

if [ "$UF2" = "1" ]; then
  # Zephyr's own post-build step (gated on CONFIG_BUILD_OUTPUT_UF2) has
  # already produced zephyr.uf2 in the build dir. We just sanity-check
  # the link address, and rename for --dev so dev/prod artifacts are
  # visually distinct even when colocated.
  ELF="$BUILD_DIR/$SAMPLE/zephyr/zephyr.elf"
  UF2_IN="$BUILD_DIR/$SAMPLE/zephyr/zephyr.uf2"
  UF2_OUT="$BUILD_DIR/$SAMPLE/zephyr/$UF2_NAME"
  if [ ! -f "$UF2_IN" ]; then
    echo "expected UF2 not found: $UF2_IN" >&2
    echo "  (CONFIG_BUILD_OUTPUT_UF2 should have produced it — check the cmake log)" >&2
    exit 1
  fi

  # Sanity check: the Adafruit UF2 bootloader expects the application at
  # 0x26000 (after MBR + SoftDevice region). If the linker placed
  # _vector_table anywhere else, flashing the resulting UF2 either fails
  # silently or — worse — corrupts something. This catches PM/DT/Kconfig
  # drift before we hand the user a bricking artifact.
  NM=$(command -v arm-zephyr-eabi-nm \
       || ls /opt/toolchains/zephyr-sdk-*/arm-zephyr-eabi/bin/arm-zephyr-eabi-nm 2>/dev/null | head -1)
  if [ -z "$NM" ]; then
    echo "WARN: arm-zephyr-eabi-nm not found — skipping link address check." >&2
  else
    ADDR=$("$NM" "$ELF" | awk '$3 == "_vector_table" { print $1 }')
    if [ "$ADDR" != "00026000" ]; then
      echo "ERROR: _vector_table is at 0x$ADDR, expected 0x00026000 for Adafruit UF2." >&2
      echo "       Partition layout drifted — check pm_static.yml / overlay slot0_partition." >&2
      exit 1
    fi
    echo "Link address OK: _vector_table at 0x$ADDR"
  fi

  if [ "$UF2_IN" != "$UF2_OUT" ]; then
    mv "$UF2_IN" "$UF2_OUT"
  fi
  echo "UF2: $UF2_OUT"
fi
