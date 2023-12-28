// SPDX-License-Identifier: GPL-2.0
#define BOOT_CTYPE_H
#include "misc.h"
#include "error.h"
#include "../string.h"

static u8 compute_checksum(u8 *buffer, u32 length)
{
	u8 *end = buffer + length;
	u8 sum = 0;

	while (buffer < end)
		sum += *(buffer++);

	return sum;
}

/* Search a block of memory for the RSDP signature. */
static u8 *scan_mem_for_rsdp(u8 *start, u32 length)
{
	struct acpi_table_rsdp *rsdp;
	u8 *address, *end;

	end = start + length;

	/* Search from given start address for the requested length */
	for (address = start; address < end; address += ACPI_RSDP_SCAN_STEP) {
		/*
		 * Both RSDP signature and checksum must be correct.
		 * Note: Sometimes there exists more than one RSDP in memory;
		 * the valid RSDP has a valid checksum, all others have an
		 * invalid checksum.
		 */
		rsdp = (struct acpi_table_rsdp *)address;

		/* BAD Signature */
		if (!ACPI_VALIDATE_RSDP_SIG(rsdp->signature))
			continue;

		/* Check the standard checksum */
		if (compute_checksum((u8 *)rsdp, ACPI_RSDP_CHECKSUM_LENGTH))
			continue;

		/* Check extended checksum if table version >= 2 */
		if ((rsdp->revision >= 2) &&
		    (compute_checksum((u8 *)rsdp, ACPI_RSDP_XCHECKSUM_LENGTH)))
			continue;

		/* Signature and checksum valid, we have found a real RSDP */
		return address;
	}
	return NULL;
}

/* Search RSDP address in EBDA. */
static acpi_physical_address bios_get_rsdp_addr(void)
{
	unsigned long address;
	u8 *rsdp;

	/* Get the location of the Extended BIOS Data Area (EBDA) */
	address = *(u16 *)ACPI_EBDA_PTR_LOCATION;
	address <<= 4;

	/*
	 * Search EBDA paragraphs (EBDA is required to be a minimum of
	 * 1K length)
	 */
	if (address > 0x400) {
		rsdp = scan_mem_for_rsdp((u8 *)address, ACPI_EBDA_WINDOW_SIZE);
		if (rsdp)
			return (acpi_physical_address)(unsigned long)rsdp;
	}

	/* Search upper memory: 16-byte boundaries in E0000h-FFFFFh */
	rsdp = scan_mem_for_rsdp((u8 *) ACPI_HI_RSDP_WINDOW_BASE,
					ACPI_HI_RSDP_WINDOW_SIZE);
	if (rsdp)
		return (acpi_physical_address)(unsigned long)rsdp;

	return 0;
}

/* Return RSDP address on success, otherwise 0. */
acpi_physical_address get_rsdp_addr(void)
{
	acpi_physical_address pa;

	pa = boot_params->acpi_rsdp_addr;

	if (!pa)
		pa = bios_get_rsdp_addr();

	return pa;
}
