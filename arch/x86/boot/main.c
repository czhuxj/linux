// SPDX-License-Identifier: GPL-2.0-only
/* -*- linux-c -*- ------------------------------------------------------- *
 *
 *   Copyright (C) 1991, 1992 Linus Torvalds
 *   Copyright 2007 rPath, Inc. - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author H. Peter Anvin
 *
 * ----------------------------------------------------------------------- */

/*
 * Main module for the real-mode kernel code
 */
#include <linux/build_bug.h>

#include "boot.h"
#include "string.h"

struct boot_params boot_params __attribute__((aligned(16)));

char *HEAP = _end;
char *heap_end = _end;		/* Default end of heap = no heap */

/*
 * Copy the header into the boot parameter block.
 */
static void copy_boot_params(void)
{
	BUILD_BUG_ON(sizeof(boot_params) != 4096);
	memcpy(&boot_params.hdr, &hdr, sizeof(hdr));
}

/*
 * Query the keyboard lock status as given by the BIOS, and
 * set the keyboard repeat rate to maximum.  Unclear why the latter
 * is done here; this might be possible to kill off as stale code.
 */
static void keyboard_init(void)
{
	struct biosregs ireg, oreg;
	initregs(&ireg);

	ireg.ah = 0x02;		/* Get keyboard status */
	intcall(0x16, &ireg, &oreg);
	boot_params.kbd_status = oreg.al;

	ireg.ax = 0x0305;	/* Set keyboard repeat rate */
	intcall(0x16, &ireg, NULL);
}

/*
 * Tell the BIOS what CPU mode we intend to run in.
 */
static void set_bios_mode(void)
{
#ifdef CONFIG_X86_64
	struct biosregs ireg;

	initregs(&ireg);
	ireg.ax = 0xec00;
	ireg.bx = 2;
	intcall(0x15, &ireg, NULL);
#endif
}

static void init_heap(void)
{
	char *stack_end;

	if (boot_params.hdr.loadflags & CAN_USE_HEAP) {
		asm("leal %P1(%%esp),%0"
		    : "=r" (stack_end) : "i" (-STACK_SIZE));

		heap_end = (char *)
			((size_t)boot_params.hdr.heap_end_ptr + 0x200);
		if (heap_end > stack_end)
			heap_end = stack_end;
	} else {
		/* Boot protocol 2.00 only, no heap available */
		puts("WARNING: Ancient bootloader, some functionality "
		     "may be limited!\n");
	}
}

void main(void)
{
	/* First, copy the boot header into the "zeropage" */
	copy_boot_params();

	/* Initialize the early-boot console */
	console_init();
	if (cmdline_find_option_bool("debug"))
		puts("early console in setup code\n");

	/* End of heap check */
	init_heap();

	/* Make sure we have all the proper CPU support */
	if (validate_cpu()) {
		puts("Unable to boot - please use a kernel appropriate "
		     "for your CPU.\n");
		die();
	}

	/* Tell the BIOS what CPU mode we intend to run in. */
	set_bios_mode();

	/* Detect memory layout */
	detect_memory();

	/* Set keyboard repeat rate (why?) and query the lock flags */
	keyboard_init();

	/* Query EDD information */
#if defined(CONFIG_EDD) || defined(CONFIG_EDD_MODULE)
	query_edd();
#endif

	/* Set the video mode */
	set_video();

	/* Do the last things and invoke protected mode */
	go_to_protected_mode();
}
