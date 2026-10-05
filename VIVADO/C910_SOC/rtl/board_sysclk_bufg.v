// Board GCIO reference clock distribution only; this is NOT a PLL/MMCM.
// Keep the input BUFG in the Bank 64 CMT and use dedicated BACKBONE routing
// to the DDR3 MIG MMCM in Bank 66. No clock frequency conversion is performed.
module board_sysclk_bufg (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_in CLK",
       X_INTERFACE_PARAMETER = "FREQ_HZ 250000000" *) input wire clk_in,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_out CLK",
       X_INTERFACE_PARAMETER = "FREQ_HZ 250000000" *) output wire clk_out
);
    (* DONT_TOUCH = "TRUE" *) BUFG clk_bufg (
        .I(clk_in),
        .O(clk_out)
    );
endmodule
