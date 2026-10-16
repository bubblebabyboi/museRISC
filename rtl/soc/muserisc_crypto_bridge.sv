// Scalar-MMIO to AXI4-Lite bridge for muse_crypto_top.
// The SoC fabric (muserisc_soc_fabric) holds its device access
// while stall_o is asserted, so one 32-bit uncached load/store
// becomes one AXI-Lite transaction: issue in IDLE, complete
// the access in the cycle RVALID/BVALID is presented.
// 32-bit aligned accesses only (the register map in
// sw/muse_crypto.h); AMO/LR/SC and vector accesses to this
// window are not supported, as on typical device MMIO.
`default_nettype none
module muserisc_crypto_bridge (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        sel_i,
    input  wire        re_i,
    input  wire [7:0]  be_i,
    input  wire [7:0]  addr_i,
    input  wire [63:0] wdata_i,
    output wire [63:0] rdata_o,
    output wire        stall_o
);
  typedef enum logic [1:0] {IDLE, RD, WR} state_t;
  state_t state_q;

  logic [31:0] axi_rdata;
  logic [1:0]  axi_bresp, axi_rresp;
  logic        axi_awready, axi_wready, axi_bvalid;
  logic        axi_arready, axi_rvalid;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [1:0]  unused_resp;
  assign unused_resp = axi_bresp ^ axi_rresp;
  /* verilator lint_on UNUSEDSIGNAL */

  logic req_rd, req_wr;
  assign req_rd = sel_i && re_i;
  assign req_wr = sel_i && (be_i != 8'd0) && !re_i;

  logic rd_done, wr_done;
  assign rd_done = (state_q == RD) && axi_rvalid;
  assign wr_done = (state_q == WR) && axi_bvalid;
  assign stall_o = (state_q == IDLE && (req_rd || req_wr)) ||
                   (state_q == RD && !axi_rvalid) ||
                   (state_q == WR && !axi_bvalid);
  assign rdata_o = addr_i[2] ? {axi_rdata, 32'd0}
                              : {32'd0, axi_rdata};

  muse_crypto_top u_crypto (
      .clk(clk_i), .rst_n(rst_ni),
      .s_axi_awaddr(addr_i),
      .s_axi_awvalid(state_q == IDLE && req_wr),
      .s_axi_awready(axi_awready),
      .s_axi_wdata(addr_i[2] ? wdata_i[63:32] : wdata_i[31:0]),
      .s_axi_wvalid(state_q == IDLE && req_wr),
      .s_axi_wready(axi_wready),
      .s_axi_bresp(axi_bresp),
      .s_axi_bvalid(axi_bvalid),
      .s_axi_bready(state_q == WR),
      .s_axi_araddr(addr_i),
      .s_axi_arvalid(state_q == IDLE && req_rd),
      .s_axi_arready(axi_arready),
      .s_axi_rdata(axi_rdata),
      .s_axi_rresp(axi_rresp),
      .s_axi_rvalid(axi_rvalid),
      .s_axi_rready(state_q == RD));

  /* verilator lint_off UNUSEDSIGNAL */
  logic unused_ready;
  assign unused_ready = axi_awready ^ axi_wready ^ axi_arready;
  /* verilator lint_on UNUSEDSIGNAL */

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
    end else begin
      unique case (state_q)
        IDLE: begin
          if (req_rd) state_q <= RD;
          else if (req_wr) state_q <= WR;
        end
        RD: if (rd_done) state_q <= IDLE;
        WR: if (wr_done) state_q <= IDLE;
        default: state_q <= IDLE;
      endcase
    end
  end
endmodule
`default_nettype wire
