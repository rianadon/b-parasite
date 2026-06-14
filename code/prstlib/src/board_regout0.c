/*
 * Boot-time UICR.REGOUT0 programmer for bparasite/nRF52840.
 *
 * The chip's VDD output voltage in high-voltage mode (VDDH >= 2.5 V, e.g.
 * CR2032 wired to VDDH) is stored in UICR.REGOUT0. The user picks the
 * desired voltage at build time via CONFIG_BPARASITE_REGOUT0_*; this hook
 * writes UICR on first boot, then resets so the new voltage takes effect.
 *
 * Two paths:
 *   - Fast path: when the desired bits are a subset of the current bits
 *     (1->0 only), do a single-word partial write — no erase.
 *   - Slow path: snapshot the entire 4 KiB UICR region into a raw word
 *     buffer, erase, modify REGOUT0 in the snapshot (via NRF_UICR_Type
 *     cast for type-safe field access), then write back every word that
 *     wasn't already erased flash. NRF_UICR_Type covers only the named
 *     fields and is smaller than the 4 KiB region, so we can't size the
 *     snapshot from it — using the raw chip-spec size preserves any UICR
 *     words past the struct (CUSTOMER[], NRFFW config, future MDK additions).
 *
 * Only runs when MAINREGSTATUS == HIGH. In normal-voltage mode the
 * regulator is bypassed and REGOUT0 has no effect.
 *
 * Registered as SYS_INIT(PRE_KERNEL_1) so it runs before any driver
 * that depends on a specific VDD. Requires prstlib to be built as a
 * zephyr_library so the init record survives the link.
 */

#if defined(CONFIG_BOARD_BPARASITE_NRF52840) && !defined(CONFIG_BPARASITE_REGOUT0_DEFAULT)

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <zephyr/init.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/util.h>
#include <hal/nrf_power.h>

/* nRF52840 UICR is a fixed 4 KiB region. NRF_UICR_Type only covers the
 * named fields and may be smaller than this; we still want to round-trip
 * the whole region so user/toolchain words past the struct survive the
 * erase. The assertion below just bounds-checks the REGOUT0 field cast.
 */
#define UICR_REGION_BYTES 0x1000u
#define UICR_REGION_WORDS (UICR_REGION_BYTES / sizeof(uint32_t))

BUILD_ASSERT(sizeof(NRF_UICR_Type) <= UICR_REGION_BYTES,
	     "NRF_UICR_Type exceeds the 4 KiB UICR region");

static inline void nvmc_wait_ready(void)
{
	while (NRF_NVMC->READY == NVMC_READY_READY_Busy) {
	}
}

static inline void nvmc_set_write(void)
{
	NRF_NVMC->CONFIG = NVMC_CONFIG_WEN_Wen << NVMC_CONFIG_WEN_Pos;
	nvmc_wait_ready();
}

static inline void nvmc_set_erase(void)
{
	NRF_NVMC->CONFIG = NVMC_CONFIG_WEN_Een << NVMC_CONFIG_WEN_Pos;
	nvmc_wait_ready();
}

static inline void nvmc_set_readonly(void)
{
	NRF_NVMC->CONFIG = NVMC_CONFIG_WEN_Ren << NVMC_CONFIG_WEN_Pos;
	nvmc_wait_ready();
}

static inline void nvmc_erase_uicr(void)
{
	nvmc_set_erase();
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

	const uint32_t new_regout0 =
		(NRF_UICR->REGOUT0 & ~((uint32_t)UICR_REGOUT0_VOUT_Msk)) |
		(want << UICR_REGOUT0_VOUT_Pos);

	/* Fast path: target bits are a subset of current bits, so the change
	 * is 1->0 only and a partial write without erase suffices.
	 */
	if ((cur & want) == want) {
		nvmc_set_write();
		NRF_UICR->REGOUT0 = new_regout0;
		nvmc_wait_ready();
		nvmc_set_readonly();
		NVIC_SystemReset();
	}

	/* Slow path: snapshot the full 4 KiB UICR, erase, restore every word
	 * that wasn't already 0xFFFFFFFF (untouched flash). Static rather
	 * than stack to keep the early-boot stack small — this only runs
	 * when the REGOUT0 choice changes (rare), so the 4 KiB BSS cost is
	 * one-shot. The struct cast gives type-safe REGOUT0 access; the
	 * BUILD_ASSERT guarantees REGOUT0 sits inside the buffer.
	 */
	static uint32_t snapshot[UICR_REGION_WORDS];
	memcpy(snapshot, (const void *)NRF_UICR, UICR_REGION_BYTES);
	((NRF_UICR_Type *)snapshot)->REGOUT0 = new_regout0;

	nvmc_erase_uicr();
	nvmc_set_write();

	volatile uint32_t *dst = (volatile uint32_t *)NRF_UICR;
	for (size_t i = 0; i < UICR_REGION_WORDS; i++) {
		if (snapshot[i] != 0xFFFFFFFFu) {
			dst[i] = snapshot[i];
			nvmc_wait_ready();
		}
	}
	nvmc_set_readonly();
	NVIC_SystemReset();

	return 0;
}

SYS_INIT(board_regulator_init, PRE_KERNEL_1, 0);

#endif  /* CONFIG_BOARD_BPARASITE_NRF52840 && !CONFIG_BPARASITE_REGOUT0_DEFAULT */
