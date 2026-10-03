ENTRY(_start)

MEMORY
{
  BRAM (rwx) : ORIGIN = 0x00010000, LENGTH = 64K
}

SECTIONS
{
  .text : {
    KEEP(*(.text.init))
    *(.text*)
  } > BRAM

  .rodata : {
    . = ALIGN(4);
    *(.rodata*)
  } > BRAM

  .data : {
    *(.sdata*)
    *(.data*)
  } > BRAM

  .bss (NOLOAD) : {
    __bss_start = .;
    *(.sbss*)
    *(.bss*)
    *(COMMON)
    __bss_end = .;
  } > BRAM

  __stack_top = ORIGIN(BRAM) + LENGTH(BRAM);
}
