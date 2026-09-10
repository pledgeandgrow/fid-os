/* linker/kernel.ld — Linker script for Fides OS kernel
 *
 * Multiboot2 kernel loaded at 1MB physical.
 * Higher-half mapping is NOT used — we run at 1MB for simplicity.
 *
 * Sections:
 *   .text   — code (read+execute)
 *   .rodata — read-only data (strings, constants)
 *   .data   — initialized data (read+write)
 *   .bss    — uninitialized data (zeroed by boot code)
 *   .stack  — kernel stack (16KB)
 */

ENTRY(_start)

SECTIONS
{
    /* Load at 1MB (standard Multiboot load address) */
    . = 1M;

    /* Multiboot2 header must be in the first 32KB and aligned to 8 bytes */
    .multiboot2 : ALIGN(8)
    {
        KEEP(*(.multiboot2))
    }

    /* Code */
    .text : ALIGN(4K)
    {
        *(.text .text.*)
    }

    /* Read-only data */
    .rodata : ALIGN(4K)
    {
        *(.rodata .rodata.*)
    }

    /* Initialized data */
    .data : ALIGN(4K)
    {
        *(.data .data.*)
    }

    /* Uninitialized data (zeroed by boot code) */
    .bss : ALIGN(4K)
    {
        *(COMMON)
        *(.bss .bss.*)

        /* Kernel stack — 16KB, 16-byte aligned */
        . = ALIGN(16);
        __stack_bottom = .;
        . += 16K;
        __stack_top = .;
    }

    /* Discard unneeded sections */
    /DISCARD/ : {
        *(.comment)
        *(.note .note.*)
        *(.eh_frame .eh_frame.*)
    }
}
