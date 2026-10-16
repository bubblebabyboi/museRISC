// SoC memory fabric (issue #4 + L1 caches): routes the CPU's
// memory-bus master port (protocol in rtl/core/muserisc_cpu.sv)
// either to the external RAM bus (PA >= RAM_BASE, passed
// through unchanged: line bursts and single beats) or to the
// on-chip devices through a single-beat device port.
//
// Device port: one access at a time. An accepted request is
// presented on dev_* for one or more cycles (ACC) until
// dev_stall_i is low (only the crypto bridge stalls); dev_re_o
// (data load) and a nonzero dev_be_o (store) are asserted only
// in ACC, so read side effects (PLIC claim, UART RBR/IIR) and
// writes happen exactly once. The read data is captured at the
// end of ACC and returned one cycle later (RSP) as a single
// response beat; stores get a single ack beat. Instruction
// fetches (req_inst) read without asserting dev_re_o (boot ROM).
// The bus carries one transaction at a time, so the response
// mux needs no arbitration.
`default_nettype none
module muserisc_soc_fabric #(
    parameter logic [63:0] RAM_BASE = 64'h0000_0000_8000_0000
) (
    input  wire        clk_i,
    input  wire        rst_ni,
    // From the CPU (mbus master)
    input  wire        m_req_valid_i,
    output logic       m_req_ready_o,
    input  wire [63:0] m_req_addr_i,
    input  wire        m_req_write_i,
    input  wire [7:0]  m_req_len_i,
    input  wire [63:0] m_req_wdata_i,
    input  wire [7:0]  m_req_be_i,
    input  wire        m_req_last_i,
    input  wire        m_req_inst_i,
    output logic       m_rsp_valid_o,
    output logic [63:0] m_rsp_rdata_o,
    output logic       m_rsp_last_o,
    // To external RAM (mbus master, pass-through)
    output logic       r_req_valid_o,
    input  wire        r_req_ready_i,
    output logic [63:0] r_req_addr_o,
    output logic       r_req_write_o,
    output logic [7:0] r_req_len_o,
    output logic [63:0] r_req_wdata_o,
    output logic [7:0] r_req_be_o,
    output logic       r_req_last_o,
    output logic       r_req_inst_o,
    input  wire        r_rsp_valid_i,
    input  wire [63:0] r_rsp_rdata_i,
    input  wire        r_rsp_last_i,
    // Device port
    output logic       dev_sel_o,     // an access is being presented
    output logic [63:0] dev_addr_o,
    output logic       dev_re_o,
    output logic [7:0] dev_be_o,
    output logic [63:0] dev_wdata_o,
    input  wire [63:0] dev_rdata_i,
    input  wire        dev_stall_i
);
  typedef enum logic [1:0] {D_IDLE, D_ACC, D_RSP} dstate_e;
  dstate_e     dstate_q;
  logic [63:0] a_q, wdata_q, rdata_q;
  logic [7:0]  be_q;
  logic        write_q, inst_q;
  logic        to_ram;

  assign to_ram = (m_req_addr_i >= RAM_BASE);

  always_comb begin
    r_req_valid_o = m_req_valid_i && to_ram;
    r_req_addr_o = m_req_addr_i;
    r_req_write_o = m_req_write_i;
    r_req_len_o = m_req_len_i;
    r_req_wdata_o = m_req_wdata_i;
    r_req_be_o = m_req_be_i;
    r_req_last_o = m_req_last_i;
    r_req_inst_o = m_req_inst_i;
    m_req_ready_o = to_ram ? r_req_ready_i : (dstate_q == D_IDLE);
    m_rsp_valid_o = r_rsp_valid_i || (dstate_q == D_RSP);
    m_rsp_rdata_o = (dstate_q == D_RSP) ? rdata_q : r_rsp_rdata_i;
    m_rsp_last_o = (dstate_q == D_RSP) || r_rsp_last_i;
    dev_sel_o = (dstate_q == D_ACC);
    dev_addr_o = a_q;
    dev_re_o = (dstate_q == D_ACC) && !write_q && !inst_q;
    dev_be_o = ((dstate_q == D_ACC) && write_q) ? be_q : 8'd0;
    dev_wdata_o = wdata_q;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dstate_q <= D_IDLE;
      a_q <= 64'd0;
      wdata_q <= 64'd0;
      rdata_q <= 64'd0;
      be_q <= 8'd0;
      write_q <= 1'b0;
      inst_q <= 1'b0;
    end else begin
      unique case (dstate_q)
        D_IDLE: begin
          if (m_req_valid_i && !to_ram) begin
            a_q <= m_req_addr_i;
            wdata_q <= m_req_wdata_i;
            be_q <= m_req_be_i;
            write_q <= m_req_write_i;
            inst_q <= m_req_inst_i;
            dstate_q <= D_ACC;
          end
        end
        D_ACC: begin
          if (!dev_stall_i) begin
            rdata_q <= dev_rdata_i;
            dstate_q <= D_RSP;
          end
        end
        default: dstate_q <= D_IDLE;  // D_RSP
      endcase
    end
  end

`ifndef SYNTHESIS
  // Low until reset: pre-reset state is arbitrary under
  // +verilator+rand+reset+2. A plain always, not always_ff, so the
  // initial block may also write it (IEEE 1800 9.2.2.4: an
  // always_ff variable has no other writer; a declaration
  // initialiser trips Verilator's PROCASSINIT instead).
  logic chk_live_q;
  initial chk_live_q = 1'b0;
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) chk_live_q <= 1'b0;
    else chk_live_q <= 1'b1;
  end
  // Devices only see single beats (I/O is never cacheable).
  a_dev_single: assert property (@(posedge clk_i) disable iff (!chk_live_q)
      (m_req_valid_i && !to_ram) |-> (m_req_len_i == 8'd0))
    else $error("soc_fabric: burst to a device address");
  a_rsp_excl: assert property (@(posedge clk_i) disable iff (!chk_live_q)
      !(r_rsp_valid_i && (dstate_q == D_RSP)))
    else $error("soc_fabric: overlapping responses");
`endif
endmodule
`default_nettype wire
