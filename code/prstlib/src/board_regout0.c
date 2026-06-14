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
 */

#if defined(CONFIG_BOARD_BPARASITE_NRF52840) && !defined(CONFIG_BPARASITE_REGOUT0_DEFAULT)

#include <stdint.h>
#include <string.h>

#include <zephyr/init.h>
#include <zephyr/kernel.h>
#include <hal/nrf_power.h>
#include <nrfx_nvmc.h>

static uint32_t desired_vout(void)
{
#if CONFIG_BPARASITE_REGOUT0_2V1
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

	int err = nrfx_nvmc_uicr_erase();
	__ASSERT(err == 0, "nrfx_nvmc_uicr_erase failed: %d", err);

	nrfx_nvmc_bytes_write(NRF_UICR_BASE, &tmp, sizeof(tmp));
	while (!nrfx_nvmc_write_done_check()) {
	}

	NVIC_SystemReset();
	return 0;
}

SYS_INIT(board_regulator_init, PRE_KERNEL_1, 0);

#endif  /* CONFIG_BOARD_BPARASITE_NRF52840 && !CONFIG_BPARASITE_REGOUT0_DEFAULT */
