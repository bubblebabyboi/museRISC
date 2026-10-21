// Debug: first traps and first core AXI reads during a sochash run.
module test_sigil_dbg2();
  import tb_type_defines_pkg::*;
  `include "sigil_test_utils.svh"
  `define S tb.card.fpga.CL.SIGIL
  int ntrap = 0, nrd = 0;
  always @(posedge `S.clk_i) begin
    if (`S.u_top.trap_o && ntrap < 6) begin
      ntrap++;
      $display("[%t] TRAP cause=%h pc=%h", $realtime, `S.u_top.trap_cause_o, `S.u_top.trap_pc_o);
    end
    if (`S.m_axi_arvalid && `S.m_axi_arready && nrd < 12) begin
      nrd++;
      $display("[%t] CORE AR addr=%h len=%0d size=%0d", $realtime, `S.m_axi_araddr, `S.m_axi_arlen, `S.m_axi_arsize);
    end
    if (`S.m_axi_rvalid && `S.m_axi_rready && nrd < 12)
      $display("[%t] CORE R data[63:0]=%h resp=%0d last=%b", $realtime, `S.m_axi_rdata[63:0], `S.m_axi_rresp, `S.m_axi_rlast);
  end
  initial begin
    bit ok;
    sigil_power_up();
    sigil_load_pcis({`SIGIL_FW_DIR, "hash_soc_test.bin"}, 64'h0);
    $display("[%t] boot_pc=%h cache_en=%b in_reset=%b", $realtime, `S.u_top.boot_pc_i, `S.u_top.cache_en_i, `S.u_top.soc_in_reset_o);
    sigil_run("SOC HASH PASS", "", 100, ok);
    $display("[%t] boot_pc=%h cache_en=%b in_reset=%b", $realtime, `S.u_top.boot_pc_i, `S.u_top.cache_en_i, `S.u_top.soc_in_reset_o);
    sigil_finish();
  end
endmodule
