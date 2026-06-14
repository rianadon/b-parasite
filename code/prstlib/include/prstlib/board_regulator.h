#ifndef PRSTLIB_BOARD_REGULATOR_H_
#define PRSTLIB_BOARD_REGULATOR_H_

/*
 * Program UICR.REGOUT0 to the value selected by CONFIG_BPARASITE_REGOUT0_*
 * if it isn't already set. Triggers a system reset when it writes UICR.
 * No-op on boards / configs that don't use this feature.
 *
 * Must be called before any code that depends on a specific VDD — earlier
 * is better. prst_adc_init() calls it first thing.
 */
void prst_board_regulator_init(void);

#endif  /* PRSTLIB_BOARD_REGULATOR_H_ */
