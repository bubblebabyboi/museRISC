  // ---- fe-trace (scratch copy only, never committed): retired-instruction
  // stream in Spike --log-commits format for the front-end study.
  logic [31:0] fet_i_exmem, fet_i_memwb;
  logic [63:0] fet_a_memwb;
  always_ff @(posedge clk_i) begin
    if (!u_core.trap_take && perf_upd) begin
      fet_i_exmem <= u_core.idex_instr_q;
      fet_i_memwb <= fet_i_exmem;
      fet_a_memwb <= u_core.exmem_addr_q;
    end
  end
  int fet_fd;
  bit fet_init, fet_on;
  initial begin fet_fd = 0; fet_init = 0; fet_on = 0; end
  /* verilator lint_off BLKSEQ */
  always @(posedge clk_i) begin
    if (perf_retire) begin
      if (!fet_init) begin
        string path;
        fet_init = 1;
        if ($value$plusargs("fetrace=%s", path)) begin fet_fd = $fopen(path, "w"); fet_on = 1; end
      end
      if (fet_on) begin
        if (fet_i_memwb[1:0] == 2'b11)
          $fwrite(fet_fd, "core   0: 3 0x%016h (0x%08h)", u_core.memwb_pc_q, fet_i_memwb);
        else
          $fwrite(fet_fd, "core   0: 3 0x%016h (0x%04h)", u_core.memwb_pc_q, fet_i_memwb[15:0]);
        if (u_core.memwb_reg_write_q && !u_core.memwb_fp_write_q && u_core.memwb_rd_q != 5'd0)
          $fwrite(fet_fd, " x%0d 0x%016h", u_core.memwb_rd_q, u_core.memwb_result_q);
        $fwrite(fet_fd, " mem 0x%016h\n", fet_a_memwb);
      end
    end
  end
  /* verilator lint_on BLKSEQ */
