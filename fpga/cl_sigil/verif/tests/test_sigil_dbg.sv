// Debug: one PCIS write with handshake monitors (issue #54 bring-up).
module test_sigil_dbg();
  import tb_type_defines_pkg::*;
  `include "sigil_test_utils.svh"
  `define C tb.card.fpga.CL
  always @(posedge `C.gen_clk_main_a0) begin
    if (`C.sh_cl_dma_pcis_awvalid) $display("[%t] PCIS aw v=%b r=%b addr=%h len=%0d size=%0d id=%h", $realtime, `C.sh_cl_dma_pcis_awvalid, `C.cl_sh_dma_pcis_awready, `C.sh_cl_dma_pcis_awaddr, `C.sh_cl_dma_pcis_awlen, `C.sh_cl_dma_pcis_awsize, `C.sh_cl_dma_pcis_awid);
    if (`C.sh_cl_dma_pcis_wvalid) $display("[%t] PCIS w v=%b r=%b last=%b", $realtime, `C.sh_cl_dma_pcis_wvalid, `C.cl_sh_dma_pcis_wready, `C.sh_cl_dma_pcis_wlast);
    if (`C.p_awvalid) $display("[%t] XBAR.XDMA aw r=%b", $realtime, `C.p_awready);
    if (`C.p_wvalid) $display("[%t] XBAR.XDMA w r=%b", $realtime, `C.p_wready);
    if (`C.d_awvalid) $display("[%t] DDRA aw r=%b addr=%h", $realtime, `C.d_awready, `C.d_awaddr);
    if (`C.d_wvalid) $display("[%t] DDRA w r=%b", $realtime, `C.d_wready);
    if (`C.d_bvalid) $display("[%t] DDRA b rdy=%b", $realtime, `C.d_bready);
    if (`C.p_bvalid) $display("[%t] XDMA b rdy=%b", $realtime, `C.p_bready);
    if (`C.cl_sh_dma_pcis_bvalid) $display("[%t] PCIS b rdy=%b", $realtime, `C.sh_cl_dma_pcis_bready);
  end
  initial begin
    logic [511:0] r;
    sigil_power_up();
    $display("[%t] main_rst_n=%b ddr_rst=%b ddr_ready=%b", $realtime, `C.main_rst_n, `C.rst_main_sync_n, `C.ddr_ready);
    fork
      begin
        tb.poke_pcis(.addr(64'h0), .data({16{32'h1234_5678}}), .strb({64{1'b1}}));
        tb.peek_pcis(.addr(64'h0), .data(r));
        $display("[%t] readback %h", $realtime, r[63:0]);
      end
      begin #20us; $display("[%t] WATCHDOG", $realtime); end
    join_any
    sigil_finish();
  end
endmodule
