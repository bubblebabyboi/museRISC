// Minimal AXI4 slave that answers every transaction with DECERR
// (issue #54). Terminates the unused SmartConnect master port in the
// F2 CL (addresses above the Shell DDR4 window) so a stray host
// access completes with an error instead of hanging. One write and
// one read in flight at a time; read bursts return ARLEN+1 beats.
`default_nettype none
module sigil_axi_decerr #(
    parameter int unsigned DATA_W = 512
) (
    input  wire              clk_i,
    input  wire              rst_ni,
    input  wire              s_awvalid_i,
    output logic             s_awready_o,
    input  wire              s_wvalid_i,
    input  wire              s_wlast_i,
    output logic             s_wready_o,
    output logic [1:0]       s_bresp_o,
    output logic             s_bvalid_o,
    input  wire              s_bready_i,
    input  wire              s_arvalid_i,
    input  wire [7:0]        s_arlen_i,
    output logic             s_arready_o,
    output logic [DATA_W-1:0] s_rdata_o,
    output logic [1:0]       s_rresp_o,
    output logic             s_rlast_o,
    output logic             s_rvalid_o,
    input  wire              s_rready_i
);
  logic aw_q, wdone_q;     // AW accepted / last W beat accepted
  logic [7:0] rleft_q;     // read beats still to send after this one

  assign s_awready_o = !aw_q && !s_bvalid_o;
  assign s_wready_o  = !wdone_q && !s_bvalid_o;
  assign s_bresp_o   = 2'b11;
  assign s_arready_o = !s_rvalid_o;
  assign s_rdata_o   = '0;
  assign s_rresp_o   = 2'b11;
  assign s_rlast_o   = (rleft_q == 8'd0);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      aw_q <= 1'b0;
      wdone_q <= 1'b0;
      s_bvalid_o <= 1'b0;
      s_rvalid_o <= 1'b0;
      rleft_q <= 8'd0;
    end else begin
      if (s_awvalid_i && s_awready_o) aw_q <= 1'b1;
      if (s_wvalid_i && s_wready_o && s_wlast_i) wdone_q <= 1'b1;
      if (aw_q && wdone_q && !s_bvalid_o) begin
        s_bvalid_o <= 1'b1;
        aw_q <= 1'b0;
        wdone_q <= 1'b0;
      end else if (s_bvalid_o && s_bready_i) begin
        s_bvalid_o <= 1'b0;
      end
      if (s_arvalid_i && s_arready_o) begin
        s_rvalid_o <= 1'b1;
        rleft_q <= s_arlen_i;
      end else if (s_rvalid_o && s_rready_i) begin
        if (rleft_q == 8'd0) s_rvalid_o <= 1'b0;
        else rleft_q <= rleft_q - 8'd1;
      end
    end
  end
endmodule
`default_nettype wire
