ENTRY(__ddr_payload_start)

MEMORY
{
  DDR_PAYLOAD (r) : ORIGIN = 0x0200000000, LENGTH = 256
}

SECTIONS
{
  .ddr_payload : {
    KEEP(*(.ddr_payload))
  } > DDR_PAYLOAD
}
