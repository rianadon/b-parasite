# b-parasite Firmware

This documentation is common to all firmwares inside the `code/` directory and covers general things like building, configuring common options, and flashing. Each firmware also has its own documentation which you should also read:

- [`samples/ble/README.md`](./samples/ble/README.md) — BLE advertising (BTHome / legacy b-parasite encoding)
- [`samples/zigbee/README.md`](./samples/zigbee/README.md) — Zigbee end device (ZHA / Zigbee2MQTT)

The instructions here are written to only apply to my `2.0.0ry1` revision (both hardware and software). For the older revision, you should refer to the original b-parasite documentation.

## Building

Use either [`scripts/build.sh`](./scripts/build.sh) or [`scripts/build-with-docker.sh`](./scripts/build-with-docker.sh) to build the firmware. I recommend using Docker (or Podman) if you have it installed.

```bash
# For BLE. Generates samples/ble/build_nrf52840_2.0.0ry1_dev/ble/zephyr/zephyr.uf2
scripts/build.sh ble nrf52840 2.0.0ry1 --uf2 -DCONFIG_BPARASITE_REGOUT0_2V1=y

# For Zigbee. Generates code/samples/zigbee/build_nrf52840_2.0.0ry1/zigbee/zephyr/zephyr.uf2
scripts/build.sh zigbee nrf52840 2.0.0ry1 --uf2  -DCONFIG_BPARASITE_REGOUT0_2V1=y
```

### Development Builds

Passing `--dev` applies the following modifications to the firmware:

- **Logs Sensor Readings Over USB Serial Port.**. Configures Zephyr to log to a USB CDC ACM virtual UART
- **Increases Log Verbosity**. `CONFIG_LOG_DEFAULT_LEVEL=4` + `CONFIG_PRSTLIB_LOG_LEVEL_DBG=y`
- **Samples much faster**. A shortened wake cadence (each sample picks its own — see `CONFIG_PRSTLIB_DEV_FAST_LOOP`)

The serial port will appear as COM* on Windows, `/dev/ttyACM*` on Linux, and `/dev/cu.usbmodem*` on MacOS. I've switched from screen to picocom to now [tio](https://github.com/tio/tio), which I wholeheartedly recommend, for connecting to serial device over the terminal.

```bash
# For a BLE development build. Generates
# samples/ble/build_nrf52840_2.0.0ry1_dev/zephyr/zephyr.uf2
scripts/build.sh ble nrf52840 2.0.0ry1 --uf2 --dev  -DCONFIG_BPARASITE_REGOUT0_2V1=y
```

Enabling USB hardware and sampling at the fast rate will quickly drain your battery. The dev builds are meant to be used when you have the b-parasite connected to USB.

## Selecting The Regulated Voltage

One of the changes I've made on the PCB is to wire `VDD` independently of `VDDH`, so you can utilize the internal LDO on the nRF52840 to step down the voltage. The lower the voltage, the longer your battery life but the weaker your wireless antenna. To change the voltage, add `-DCONFIG_BPARASITE_REGOUT0_*V*=y`) to the end of your `build.sh` command. The default is `REGOUT0_2V1`.

The choice also drives `CONFIG_BT_CTLR_TX_PWR_*`, which configures how powerful your radio will be. If you want finer control, you can override it with `-DCONFIG_PRSTLIB_RADIO_TX_PWR_DBM=0`/`4`/`8`.

| Kconfig | Chip VDD | BLE TX cap | Best for | Readings accurate down to | CR2032 life (ai estimate) |
|---|---|---|---|---|---|
| `REGOUT0_1V8` | 1.8 V | 0 dBm | Best battery life, but voltage is too low for LED to turn on | 1.3% battery | ~3.5 yr |
| `REGOUT0_2V1` | 2.1 V | 0 dBm | Recommended default for indoors. In cold temperatures, the voltage may be too low for the LED. | 5.4% battery | ~2.5–3.7 yr |
| `REGOUT0_2V4` | 2.4 V | +4 dBm | Recommended for outdoors due to more wireless range and greater LED voltage. | 16.4% battery | ~2.0–3.0 yr |

There's also `REGOUT0_2V7` (+4dBm), `REGOUT0_3V0` (+8dBm) and `REGOUT0_3V3` (+8dBm).  However, for all of these the sensor readings will scale linearly with voltage as the battery drops, instead of remaining stable. This is because the onboard LDO requires VDDH > VDD+0.3V to be stable, and CR2032 starts at 3.0V.

The voltage setting is stored in UICR flash. When the chip is booted with the firmware for the first time, it will write UICR and reboot if the voltage setting changed.

## Calibrating the Sensors

Because the LDO ensures a stable supply voltage, only one measurement is needed for calibrating the soil and light sensors.

Procedure:

1. Load a firmware with development mode (`--dev`) turned on (see *Development Builds* above) **with the same voltage configured that you will use in your firmware** . Open the serial port.
2. With the sensor sitting in **outside soil** and touching nothing, wait for log lines like:
    ```
    Read soil moisture 2: -3.24 | Raw 508 | V_drive: 2.10 | Dry: 510 | Wet: 179
    ```
   Record the **Raw** value (here, `508`) — this is your `PRSTLIB_SOIL_DRY_RAW`. Ignore "Dry"/"Wet"—they are the calibration the firmware is currently using.
3. With the sensor sitting outside or near sunlight, record the phototransistor value as well as the lux from your smartphone (there are quite a few lux meters). Look for the line that reads
    ```
    Photo: 687 lx (116 mV)
    ```
    Disregard the lux reading here, since that uses the firmware's preexisting calibration. Instead calculate `PRSTLIB_PHOTO_CURRENT_SUN_UA` = 21277 × reported current (mV) ÷ phone's illuminance reading (lux).
3. Submerge the sensor pads in tap water up to the printed line on the circuit board. Use the same Raw reading in step 2, which is now your `PRSTLIB_SOIL_WET_RAW`.
4. Build the UF2

```
./scripts/build.sh ble nrf52840 2.0.0ry1 --uf2 \
  -DCONFIG_BPARASITE_REGOUT0_2V1=y \
  -DCONFIG_PRSTLIB_SOIL_DRY_RAW=510 \
  -DCONFIG_PRSTLIB_SOIL_WET_RAW=170 \
  -DCONFIG_PRSTLIB_PHOTO_CURRENT_SUN_UA=3546
```

For the Zigbee firmware, replace `ble` with `zigbee`.

## Bootloader

I flash the Adafruit UF2 bootloader to the board. The b-parasite specific configuration is located in [my Adafruit_nRF52_Bootloader fork](https://github.com/rianadon/Adafruit_nRF52_Bootloader).
