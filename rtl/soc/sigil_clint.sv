// RISC-V CLINT (single hart): msip @0x0, mtimecmp @0x4000,
// mtime @0xBFF8, one mtime tick per clock. Bus is the core's
// aligned-64-bit data word: addr_i is the exact byte offset,
// be_i/wdata_i are aligned-word lanes, rdata_o is the aligned
// 64-bit word containing addr_i (mirrors tb/cpp/soc_tb.cpp).
`default_nettype none
module sigil_clint (
    input  wire        clk_i,
    input  wire        rst_ni,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [15:0] addr_i,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [7:0]  be_i,
    input  wire [63:0] wdata_i,
    output wire [63:0] rdata_o,
    output wire        irq_m_timer_o,
    output wire        irq_m_soft_o
);
  logic [31:0] msip_q;
  logic [63:0] mtime_q, mtimecmp_q;

  logic [15:0] align_off;
  assign align_off = {addr_i[15:3], 3'b000};
  assign rdata_o = (align_off == 16'h0000) ? {32'd0, msip_q} :
                   (align_off == 16'h4000) ? mtimecmp_q :
                   (align_off == 16'hBFF8) ? mtime_q : 64'd0;
  assign irq_m_timer_o = (mtime_q >= mtimecmp_q);
  assign irq_m_soft_o = msip_q[0];

  // Byte-wise merge of a store over the next register value
  // (mtime write overrides this cycle's increment).
  function automatic logic [63:0] merge_bytes(
      input logic [63:0] cur, input logic [63:0] wdata,
      input logic [7:0] be);
    logic [63:0] r;
    r = cur;
    for (int i = 0; i < 8; i++) begin
      if (be[i]) r[8*i +: 8] = wdata[8*i +: 8];
    end
    return r;
  endfunction

  logic [31:0] msip_merged;
  always_comb begin
    for (int i = 0; i < 4; i++) begin
      msip_merged[8*i +: 8] = be_i[i] ? wdata_i[8*i +: 8]
                                      : msip_q[8*i +: 8];
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      msip_q <= 32'd0;
      mtime_q <= 64'd0;
      mtimecmp_q <= 64'd0;
    end else begin
      mtime_q <= mtime_q + 64'd1;
      if (align_off == 16'h0000 && (be_i[3:0] != 4'd0)) begin
        msip_q <= msip_merged;
      end
      if (align_off == 16'h4000 && (be_i != 8'd0)) begin
        mtimecmp_q <= merge_bytes(mtimecmp_q, wdata_i, be_i);
      end
      if (align_off == 16'hBFF8 && (be_i != 8'd0)) begin
        mtime_q <= merge_bytes(mtime_q + 64'd1, wdata_i, be_i);
      end
    end
  end
endmodule
`default_nettype wire
