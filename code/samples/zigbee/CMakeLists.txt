cmake_minimum_required(VERSION 3.20.0)
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project("b-parasite Zigbee sample")

include_directories(src)

target_sources(app PRIVATE
  src/main.c
  src/debug_counters.c
  src/double_reset_detector.c
  src/factory_reset.c
  src/flash_fs.c
  src/prst_zb_attrs.c
  src/prst_zb_soil_moisture_defs.c
  src/restart_handler.c
  src/watchdog.c
)
