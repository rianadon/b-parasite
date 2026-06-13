# Custom revision handling for bparasite (board.yml uses format: custom).
#
# Maps the user-facing revision string (e.g. "2.0.0ry1") to the filename-safe
# active revision used by Zephyr to locate <board>_<rev>.overlay and
# <board>_<rev>_defconfig (e.g. "2_0_0_ry1").

if("${BOARD_REVISION}" STREQUAL "2.0.0ry1")
  set(ACTIVE_BOARD_REVISION "2_0_0_ry1")
else()
  # For canonical major.minor.patch revisions, just swap dots for underscores
  # to match the existing filename layout (1.0.0 -> 1_0_0, etc.).
  string(REPLACE "." "_" ACTIVE_BOARD_REVISION "${BOARD_REVISION}")
endif()
