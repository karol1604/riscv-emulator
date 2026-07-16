ENTRY(_start)

SECTIONS
{
    . = 0;

    .text :
    {
        KEEP(*(.text.start))
        *(.text .text.*)
    }

    .rodata : { *(.rodata .rodata.*) }
    .data   : { *(.data .data.*) }
    .bss    : { *(.bss .bss.*) *(COMMON) }
}
