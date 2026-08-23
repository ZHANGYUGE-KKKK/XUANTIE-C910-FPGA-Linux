ENTRY(_start)

MEMORY
{
  DDR_EXEC (rx) : ORIGIN = 0x0200000000, LENGTH = 4K
}

SECTIONS
{
  .text : {
    KEEP(*(.text.init))
    *(.text*)
    *(.rodata*)
  } > DDR_EXEC
}
