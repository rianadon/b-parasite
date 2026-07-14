# Bluetooth Low Energy (BLE)
In this sample, b-parasite sensors are periodically read and broadcast using Bluetooth Low Energy (BLE) dvertising packets.

## Configuration
Available configurations and their default values are in [`Kconfig`](./Kconfig). They are set in [`prj.conf`](./prj.conf). Here are some notable examples.

### Sleep Interval
To save energy, the board spends most of the time in a "deep sleep" state, in which most peripherals and radio are completely turned off. The period of sleep is controlled by the `PRST_SLEEP_DURATION_SEC` config.

### Advertising Duration
When it wakes up, the sample reads all sensors and keep broadcasting advertising packets for `PRST_BLE_ADV_DURATION_MSEC` before going back to sleep.

### Advertising Packet Encoding
There are different ways to encode the sensor data in a BLE advertising packet.

#### BTHome Encoding
[BTHome](https://bthome.io) is a new (as of Dec/2022) open standard for encoding sensor data in BLE applications. [Home Assistant](https://www.home-assistant.io/integrations/bthome/) supports it out of the box. This makes the deployment extra convenient, since no additional configuration is needed - Home Assistant will automatically detect b-parasites in range.

What's even more interesting is that by employing [ESPHome](https://esphome.io/) bridges with the [`bluetooth_proxy`](https://esphome.io/components/bluetooth_proxy.html) component, the range of BLE coverage can be transparently increased. Multiple ESPHome bridges will forward received BLE broadcasts to Home Assistant.

This is what a typical deployment with BTHome looks like:
![Topology with BTHome + Home Assistant](./media/drawings/ble-bthome-encoding.png)

There are two versions of BTHome encodings supported by this sample:
* `PRST_BLE_ENCODING_BTHOME_V2=y` (**default**) uses the [BTHome V2](https://bthome.io/format/), supported by Home Assistant since version `2022.12`
* `PRST_BLE_ENCODING_BTHOME_V1=y` uses the [legacy BTHome V1](https://bthome.io/v1/), which was briefly in use
#### b-parasite Encoding
`PRST_BLE_ENCODING_BPARASITE_V2=y` selects the legacy encoding, used historically in this project. This is the encoding that the [`b_parasite`](https://esphome.io/components/sensor/b_parasite.html) ESPHome component understands.

With this encoding and a ESPHome + `b_parasite` component, this is an usual deployment topology:

![Topology with Legacy encoding + Home Assistant](./media/drawings/ble-bparasite-encoding.png)

The disadvantages of this encoding are:
- Each b-parasite has to be configured in the ESPHome component
- Range is limited, unless multiple ESPHome bridges are deployed with the same static configuration

## Building

See [`code/README.md`](../../README.md) for the build script, the container wrapper, the `REGOUT0` voltage table, and the soil-moisture calibration procedure — all shared with the zigbee sample. What follows is ble-specific.

### Production build (deploy to battery)

Default `prj.conf` settings: 10-min wake cadence, 1-s advertise window, no USB stack, no logging. Pair with the `2.0.0ry1` board revision (CR2032 wired to VDDH) and pick a `REGOUT0` voltage that matches your hardware (see [`prstlib/boards/bparasite/Kconfig.regout0`](../../prstlib/boards/bparasite/Kconfig.regout0)).

```
./scripts/build-with-docker.sh ble nrf52840 2.0.0ry1 --uf2 \
  -DCONFIG_BPARASITE_REGOUT0_2V1=y
```

Output: `samples/ble/build_nrf52840_2.0.0ry1/ble/zephyr/zephyr.uf2` (~400 KB).

BLE picks its `CONFIG_BT_CTLR_TX_PWR_*` choice from `PRSTLIB_RADIO_TX_PWR_DBM`, which the `REGOUT0` choice sets (0 dBm at 1.8–2.1 V, 4 at 2.4–2.7 V, 8 at 3.0–3.3 V).

### Development build (bring-up, sensor calibration, debugging)

Same command + `--dev` (see [`code/README.md`](../../README.md#development-builds) for what the snippet turns on). For ble it also sets `CONFIG_PRST_SLEEP_DURATION_MSEC=5000`, advertising every ~6 s instead of every 10 min.

```
./scripts/build-with-docker.sh ble nrf52840 2.0.0ry1 --uf2 --dev \
  -DCONFIG_BPARASITE_REGOUT0_2V1=y
```

Output: `samples/ble/build_nrf52840_2.0.0ry1_dev/ble/zephyr/zephyr.uf2` (~445 KB).

## Battery Life
**tl;dr**: Theoretically well over two years with default settings.

While in deep sleep, the board consumes around `3.0 uA`:

![Sleep current consumption](./media/power-profile/sleep.png)

In the active broadcasting state, the average power consumption is highly dependant on the advertising interval.

With the default settings (in the `[30, 40] ms` range), we see an average of around `810 uA`:

![Broadcasting with 30 ms current consumption](./media/power-profile/broadcasting-30.png)

If for example we lower the connection interval to the SDK defaults (`[100, 150] ms`, roughly trading off range for power), the average current consumption is around `345 uA`:

![Broadcasting with 100ms current consumption](./media/power-profile/broadcasting-100.png)

With a `200 mAh` CR2032 battery, we can use [this spreadsheet](https://docs.google.com/spreadsheets/d/157JQiX20bGkTrlbvWbWRrs_WViL3MgVZffSCWRR7uAI/edit#gid=0) to estimate the battery life to over two years. Note that this is a simplified model and results in practice may vary.
