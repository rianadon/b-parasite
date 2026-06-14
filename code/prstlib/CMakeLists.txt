add_library(prstlib STATIC
	src/adc.c
	src/board_regout0.c
	src/button.c
	src/led.c
	src/sensors.c
	src/shtc3.c
)

target_include_directories(prstlib PUBLIC include)
target_link_libraries(prstlib PUBLIC zephyr_interface kernel)
