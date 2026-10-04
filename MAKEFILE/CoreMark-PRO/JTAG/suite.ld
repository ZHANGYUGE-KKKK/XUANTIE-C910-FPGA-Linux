OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { DDR (rwx) : ORIGIN = 0x200000000, LENGTH = 160M }
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
  /* The controller's libc owns 1 MiB; each module's private libc owns 16 MiB. */
  __heap_start = ALIGN(64);
  __heap_end = __heap_start + 1M;
  cm0___heap_start = __heap_end;
  cm0___heap_end = cm0___heap_start + 16M;
  cm1___heap_start = cm0___heap_end;
  cm1___heap_end = cm1___heap_start + 16M;
  cm2___heap_start = cm1___heap_end;
  cm2___heap_end = cm2___heap_start + 16M;
  cm3___heap_start = cm2___heap_end;
  cm3___heap_end = cm3___heap_start + 16M;
  cm4___heap_start = cm3___heap_end;
  cm4___heap_end = cm4___heap_start + 16M;
  cm5___heap_start = cm4___heap_end;
  cm5___heap_end = cm5___heap_start + 16M;
  cm6___heap_start = cm5___heap_end;
  cm6___heap_end = cm6___heap_start + 16M;
  cm7___heap_start = cm6___heap_end;
  cm7___heap_end = cm7___heap_start + 16M;
  cm8___heap_start = cm7___heap_end;
  cm8___heap_end = cm8___heap_start + 16M;
  __stack_top = ORIGIN(DDR) + LENGTH(DDR);
  __stack_bottom = __stack_top - 256K;
  ASSERT(cm8___heap_end <= __stack_bottom, "CoreMark-PRO suite heap/stack overlap")
  /DISCARD/ : { *(.comment) *(.note*) }
}
