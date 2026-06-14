/*
 * Boot-time UICR.REGOUT0 programmer for bparasite/nRF52840.
 *
 * The chip's VDD output voltage in high-voltage mode (VDDH ≥ 2.5 V, e.g.
 * CR2032 wired to VDDH) is stored in UICR.REGOUT0. The user picks the
 * desired voltage at build time via CONFIG_BPARASITE_REGOUT0_*; this hook
 * writes UICR on first boot, then resets so the new voltage takes effect.
 *
 * Two paths:
 *   - Fast path: when the desired bits are a subset of the current bits
 *     (1→0 only), do a single-word partial write — no erase.
 *   - Slow path: snapshot the entire UICR region (4 KiB), erase it, modify
 *     the REGOUT0 word in the snapshot, then write back every non-default
 *     word. This preserves PSELRESET, NFCPINS, APPROTECT, CUSTOMER[],
 *     NRFFW config and anything else the toolchain (now or in the future)
 *     might have stored in UICR.
 *
 * Only runs when MAINREGSTATUS == HIGH. In normal-voltage mode the
 * regulator is bypassed and REGOUT0 has no effect.
 *
 * Lives in prstlib/src/ rather than the board directory so it definitely
 * gets pulled into the link. Exposed as prst_board_regulator_init() and
 * called from prst_adc_init() — a hard reference, so the linker keeps
 * the object even though prstlib is built as a plain static library
 * (no --whole-archive).
 */

#include <stddef.h>
#include <stdint.h>

#include "prstlib/board_regulator.h"

#if defined(CONFIG_BOARD_BPARASITE_NRF52840) && !defined(CONFIG_BPARASITE_REGOUT0_DEFAULT)

#include <zephyr/kernel.h>
#include <hal/nrf_power.h>

#define UICR_SIZE_WORDS (sizeof(NRF_UICR_Type) / sizeof(uint32_t))

static inline void nvmc_wait_ready(void)
{
	while (NRF_NVMC->READY == NVMC_READY_READY_Busy) {
	}
}

static inline void nvmc_enable_write(void)
{
	NRF_NVMC->CONFIG = NVMC_CONFIG_WEN_Wen << NVMC_CONFIG_WEN_Pos;
	nvmc_wait_ready();
}

static inline void nvmc_enable_erase(void)
{
	NRF_NVMC->CONFIG = NVMC_CONFIG_WEN_Een << NVMC_CONFIG_WEN_Pos;
	nvmc_wait_ready();
}

static inline void nvmc_disable(void)
{
	NRF_NVMC->CONFIG = NVMC_CONFIG_WEN_Ren << NVMC_CONFIG_WEN_Pos;
	nvmc_wait_ready();
}

static inline void nvmc_erase_uicr(void)
{
	nvmc_enable_erase();
	NRF_NVMC->ERASEUICR = NVMC_ERASEUICR_ERASEUICR_Erase;
	nvmc_wait_ready();
}

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

void prst_board_regulator_init(void)
{
	if (nrf_power_mainregstatus_get(NRF_POWER) != NRF_POWER_MAINREGSTATUS_HIGH) {
		return;
	}

	const uint32_t want = desired_vout();
	const uint32_t cur =
		(NRF_UICR->REGOUT0 & UICR_REGOUT0_VOUT_Msk) >> UICR_REGOUT0_VOUT_Pos;

	if (cur == want) {
		return;
	}

	const uint32_t new_regout0 =
		(NRF_UICR->REGOUT0 & ~((uint32_t)UICR_REGOUT0_VOUT_Msk)) |
		(want << UICR_REGOUT0_VOUT_Pos);

	if ((cur & want) == want) {
		nvmc_enable_write();
		NRF_UICR->REGOUT0 = new_regout0;
		nvmc_wait_ready();
		nvmc_disable();
		NVIC_SystemReset();
	}

	static uint32_t snapshot[UICR_SIZE_WORDS];
	volatile uint32_t *uicr = (volatile uint32_t *)NRF_UICR_BASE;

	for (size_t i = 0; i < UICR_SIZE_WORDS; i++) {
		snapshot[i] = uicr[i];
	}

	const size_t regout0_idx =
		((uintptr_t)&NRF_UICR->REGOUT0 - (uintptr_t)NRF_UICR_BASE) /
		sizeof(uint32_t);
	snapshot[regout0_idx] = new_regout0;

	nvmc_erase_uicr();
	nvmc_enable_write();
	for (size_t i = 0; i < UICR_SIZE_WORDS; i++) {
		if (snapshot[i] != 0xFFFFFFFFu) {
			uicr[i] = snapshot[i];
			nvmc_wait_ready();
		}
	}
	nvmc_disable();
	NVIC_SystemReset();
}

#else  /* CONFIG_BOARD_BPARASITE_NRF52840 && !CONFIG_BPARASITE_REGOUT0_DEFAULT */

void prst_board_regulator_init(void)
{
}

#endif
