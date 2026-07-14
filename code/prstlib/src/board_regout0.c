/*
 * Boot-time UICR.REGOUT0 programmer for bparasite/nRF52840.
 *
 * The chip's VDD output voltage in high-voltage mode (VDDH >= 2.5 V, e.g.
 * CR2032 wired to VDDH) is stored in UICR.REGOUT0. The user picks the
 * desired voltage at build time via CONFIG_BPARASITE_REGOUT0_*; this hook
 * writes UICR on first boot, then resets so the new voltage takes effect.
 *
 * Snapshots NRF_UICR_Type, erases UICR via the nrfx HAL, modifies REGOUT0
 * in the snapshot, writes the whole struct back. Bytes past the struct
 * (chip-reserved tail) are left at 0xFFFFFFFF after the erase — NCS and
 * the Nordic toolchain don't populate them, so nothing real is lost.
 *
 * Only runs when MAINREGSTATUS == HIGH. In normal-voltage mode the
 * regulator is bypassed and REGOUT0 has no effect.
 *
 * Registered as SYS_INIT(PRE_KERNEL_1) so it runs before any driver
 * that depends on a specific VDD. Requires prstlib to be built as a
 * zephyr_library so the init record survives the link.
 *
 * If the erase fails or the post-write readback of REGOUT0 doesn't match
 * the intended value, fatal_blink() drops the CPU into an infinite LED
 * blink so a half-programmed UICR can't be left to brick the board
 * silently — the user sees the failure and pulls the battery before
 * trusting the chip.
 */

#if defined(CONFIG_BOARD_BPARASITE_NRF52840)

#include <stdint.h>
#include <string.h>

#include <zephyr/devicetree.h>
#include <zephyr/init.h>
#include <zephyr/kernel.h>
#include <hal/nrf_gpio.h>
#include <hal/nrf_power.h>
#include <nrfx_nvmc.h>

/* led0 is a node label on every bparasite board revision (base DTS +
 * per-revision overlays). At PRE_KERNEL_1 the Zephyr GPIO driver isn't
 * up yet, so fatal_blink() pokes the nrf_gpio HAL directly using the
 * absolute pin number (port*32 + pin) derived from DT.
 */
#define LED_NODE    DT_NODELABEL(led0)
#define LED_PORT    DT_PROP(DT_GPIO_CTLR(LED_NODE, gpios), port)
#define LED_PIN     DT_GPIO_PIN(LED_NODE, gpios)
#define LED_ABS_PIN NRF_GPIO_PIN_MAP(LED_PORT, LED_PIN)

static uint32_t desired_vout(void)
{
#if CONFIG_BPARASITE_REGOUT0_1V8
	return UICR_REGOUT0_VOUT_1V8;
#elif CONFIG_BPARASITE_REGOUT0_2V1
	return UICR_REGOUT0_VOUT_2V1;
#elif CONFIG_BPARASITE_REGOUT0_2V4
	return UICR_REGOUT0_VOUT_2V4;
#elif CONFIG_BPARASITE_REGOUT0_2V7
	return UICR_REGOUT0_VOUT_2V7;
#elif CONFIG_BPARASITE_REGOUT0_3V0
	return UICR_REGOUT0_VOUT_3V0;
#elif CONFIG_BPARASITE_REGOUT0_3V3
	return UICR_REGOUT0_VOUT_3V3;
#else
#error "No BPARASITE_REGOUT0_* selected"
#endif
}

__attribute__((noreturn))
static void fatal_blink(void)
{
	nrf_gpio_cfg_output(LED_ABS_PIN);
	for (;;) {
		nrf_gpio_pin_toggle(LED_ABS_PIN);
		k_busy_wait(100000);
	}
}

static int board_regulator_init(void)
{
	if (nrf_power_mainregstatus_get(NRF_POWER) != NRF_POWER_MAINREGSTATUS_HIGH) {
		return 0;
	}

	const uint32_t want = desired_vout();
	const uint32_t cur =
		(NRF_UICR->REGOUT0 & UICR_REGOUT0_VOUT_Msk) >> UICR_REGOUT0_VOUT_Pos;

	if (cur == want) {
		return 0;
	}

	NRF_UICR_Type tmp;
	memcpy(&tmp, NRF_UICR, sizeof(tmp));
	tmp.REGOUT0 = (tmp.REGOUT0 & ~((uint32_t)UICR_REGOUT0_VOUT_Msk)) |
		      (want << UICR_REGOUT0_VOUT_Pos);

	if (nrfx_nvmc_uicr_erase() != 0) {
		fatal_blink();
	}

	nrfx_nvmc_bytes_write(NRF_UICR_BASE, &tmp, sizeof(tmp));
	while (!nrfx_nvmc_write_done_check()) {
	}

	/* Readback verification: confirms the field we cared about landed.
	 * If the chip is in a state that silently drops UICR writes (APPROTECT,
	 * NVMC misconfig, hardware fault), this catches it before we reset
	 * into an unknown VDD.
	 */
	const uint32_t got =
		(NRF_UICR->REGOUT0 & UICR_REGOUT0_VOUT_Msk) >> UICR_REGOUT0_VOUT_Pos;
	if (got != want) {
		fatal_blink();
	}

	NVIC_SystemReset();
	return 0;
}

SYS_INIT(board_regulator_init, PRE_KERNEL_1, 0);

#endif  /* CONFIG_BOARD_BPARASITE_NRF52840 */
