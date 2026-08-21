ENTRY(_start)

MEMORY
{
  BOOTROM (rx) : ORIGIN = 0x00000000, LENGTH = 4K
}

SECTIONS
{
  .text : {
    KEEP(*(.text.init))
    *(.text*)
  } > BOOTROM
}
