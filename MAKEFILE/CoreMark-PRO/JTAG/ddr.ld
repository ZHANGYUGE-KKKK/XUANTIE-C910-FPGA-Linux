OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { DDR (rwx) : ORIGIN = 0x200000000, LENGTH = 16M }
SECTIONS
{
  .text : { KEEP(*(.text.init)) *(.text*) } > DDR
  .rodata : { . = ALIGN(64); *(.rodata*) *(.srodata*) } > DDR
  .data : { . = ALIGN(64); __global_pointer$ = . + 0x800; *(.sdata*) *(.data*) } > DDR
  .bss (NOLOAD) : {
    . = ALIGN(64); __bss_start = .;
    *(.sbss*) *(.bss*) *(COMMON)
    . = ALIGN(64); __bss_end = .;
  } > DDR
  __heap_start = ALIGN(64);
  __stack_top = ORIGIN(DDR) + LENGTH(DDR);
  __stack_bottom = __stack_top - 256K;
  __heap_end = __stack_bottom;
  ASSERT(__heap_start + 8M <= __heap_end, "CoreMark-PRO needs at least 8 MiB of heap")
  /DISCARD/ : { *(.comment) *(.note*) }
}
