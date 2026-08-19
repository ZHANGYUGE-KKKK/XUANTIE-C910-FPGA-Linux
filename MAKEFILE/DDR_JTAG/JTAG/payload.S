.section .ddr_payload, "a", @progbits
.globl __ddr_payload_start
.globl __ddr_payload_end

__ddr_payload_start:
    .ascii "JTAG_DDR_OK_1234\r\n"
    .space 256 - (. - __ddr_payload_start), 0

__ddr_payload_end:
