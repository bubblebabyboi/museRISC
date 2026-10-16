// museRISC CPU subsystem: muserisc_core + L1 I$ + L1 D$ + bus
// arbiter, presenting one memory-bus master port.
//
// Memory bus ("mbus", one transaction in flight, in order):
//   Request channel, valid/ready (valid never waits for ready;
//   payload, req_wdata included, stable while valid && !ready):
//     req_addr   byte address (PA). Bursts: line-aligned on the
//                first beat; each write beat carries its own
//                beat address.
//     req_write  1 = write
//     req_len    beats - 1 (0 = single beat; line bursts are
//                LINE_BYTES/8 - 1, incrementing, 8 bytes/beat)
//     req_wdata, req_be   write data / byte lanes of the aligned
//                64-bit word (req_wdata is 0 on I$ beats).
//                Single-beat reads also carry the
//                accessed lanes in req_be (I/O devices see the
//                exact access width).
//     req_last   last write beat (always 1 on reads)
//     req_inst   instruction fetch (AXI ARPROT[2] equivalent)
//   A read takes one request beat and returns len+1 response
//   beats; a write takes len+1 request beats and returns one
//   response beat. Response channel: rsp_valid (no ready: the
//   master is always waiting for it), rsp_rdata, rsp_last
//   (last beat of the transaction; 1 on write acks). The first
//   response beat may come no earlier than the cycle after the
//   request beat that completes the request. Maps 1:1 onto
//   AXI4 (AR/R for reads; AW+W/B for writes, RREADY=BREADY=1)
//   or onto a BRAM controller.
//
// Cacheability (PMA): a PA is cacheable iff cache_en_i and it
// lies in [C0_BASE, C0_BASE+C0_SIZE) or [C1_BASE, C1_BASE+
// C1_SIZE). The defaults make the soc_tb / DT DRAM window
// 0x8000_0000..0xFFFF_FFFF cacheable and everything below it
// (boot ROM, CLINT, PLIC, UART, crypto) I/O. cache_en_i is a
// strap (must not change after reset).
//
// The dbg_st_* outputs mirror every store request the core
// hands its data port (stores, SC/AMO write phases, PTE A/D
// updates) at the handshake. They exist for test harnesses
// (HTIF tohost lives in cacheable RAM and may never reach the
// bus under write-back) and can be left unconnected.
`default_nettype none
module muserisc_cpu import muserisc_cache_pkg::*; #(
    parameter int unsigned IC_SETS = 64,
    parameter int unsigned IC_WAYS = 2,
    parameter int unsigned DC_SETS = 64,
    parameter int unsigned DC_WAYS = 4,
    parameter int unsigned LINE_BYTES = 64,
    parameter logic [63:0] C0_BASE = 64'h0000_0000_8000_0000,
    parameter logic [63:0] C0_SIZE = 64'h0000_0000_8000_0000,
    parameter logic [63:0] C1_BASE = 64'h0,
    parameter logic [63:0] C1_SIZE = 64'h0
) (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire [63:0] boot_pc_i,
    input  wire        cache_en_i,
    // Memory bus master
    output logic       bus_req_valid_o,
    input  wire        bus_req_ready_i,
    output logic [63:0] bus_req_addr_o,
    output logic       bus_req_write_o,
    output logic [7:0] bus_req_len_o,
    output logic [63:0] bus_req_wdata_o,
    output logic [7:0] bus_req_be_o,
    output logic       bus_req_last_o,
    output logic       bus_req_inst_o,
    input  wire        bus_rsp_valid_i,
    input  wire [63:0] bus_rsp_rdata_i,
    input  wire        bus_rsp_last_i,
    // Trap observability / control (see muserisc_core)
    output wire        trap_o,
    output wire [63:0] trap_cause_o,
    output wire [63:0] trap_pc_o,
    input  wire        trap_halt_i,
    input  wire        irq_m_timer_i,
    input  wire        irq_m_soft_i,
    input  wire        irq_m_ext_i,
    input  wire        irq_s_timer_i,
    input  wire        irq_s_ext_i,
    // Store observation (test harnesses only)
    output logic       dbg_st_valid_o,
    output logic [63:0] dbg_st_addr_o,
    output logic [7:0] dbg_st_be_o,
    output logic [63:0] dbg_st_wdata_o,
    output logic [63:0] dbg_fetch_pa_o   // current fetch PA (diagnostics)
);
  logic        ireq_valid, ireq_ready, irsp_valid, ic_inval;
  logic [63:0] ireq_addr;
  logic [31:0] irsp_rdata;
  logic        dreq_valid, dreq_ready, drsp_valid;
  logic [63:0] dreq_addr, dreq_wdata, drsp_rdata;
  logic [1:0]  dreq_op;
  logic [7:0]  dreq_be;

  muserisc_core u_core (
      .clk_i          (clk_i),
      .rst_ni         (rst_ni),
      .boot_pc_i      (boot_pc_i),
      .ireq_valid_o   (ireq_valid),
      .ireq_ready_i   (ireq_ready),
      .ireq_addr_o    (ireq_addr),
      .irsp_valid_i   (irsp_valid),
      .irsp_rdata_i   (irsp_rdata),
      .icache_inval_o (ic_inval),
      .dreq_valid_o   (dreq_valid),
      .dreq_ready_i   (dreq_ready),
      .dreq_addr_o    (dreq_addr),
      .dreq_op_o      (dreq_op),
      .dreq_wdata_o   (dreq_wdata),
      .dreq_be_o      (dreq_be),
      .drsp_valid_i   (drsp_valid),
      .drsp_rdata_i   (drsp_rdata),
      .trap_o         (trap_o),
      .trap_cause_o   (trap_cause_o),
      .trap_pc_o      (trap_pc_o),
      .trap_halt_i    (trap_halt_i),
      .irq_m_timer_i  (irq_m_timer_i),
      .irq_m_soft_i   (irq_m_soft_i),
      .irq_m_ext_i    (irq_m_ext_i),
      .irq_s_timer_i  (irq_s_timer_i),
      .irq_s_ext_i    (irq_s_ext_i)
  );

  assign dbg_st_valid_o = dreq_valid && dreq_ready && (dreq_op == DOP_STORE);
  assign dbg_st_addr_o = dreq_addr;
  assign dbg_st_be_o = dreq_be;
  assign dbg_st_wdata_o = dreq_wdata;
  assign dbg_fetch_pa_o = ireq_addr;

  // I$ <-> arbiter m0
  logic        ib_valid, ib_ready, ib_rsp_valid;
  logic [63:0] ib_addr;
  logic [7:0]  ib_len, ib_be;
  // D$ <-> arbiter m1
  logic        db_valid, db_ready, db_write, db_last, db_rsp_valid;
  logic [63:0] db_addr, db_wdata;
  logic [7:0]  db_len, db_be;

  muserisc_icache #(
      .SETS(IC_SETS), .WAYS(IC_WAYS), .LINE_BYTES(LINE_BYTES),
      .C0_BASE(C0_BASE), .C0_SIZE(C0_SIZE),
      .C1_BASE(C1_BASE), .C1_SIZE(C1_SIZE)
  ) u_icache (
      .clk_i           (clk_i),
      .rst_ni          (rst_ni),
      .cache_en_i      (cache_en_i),
      .inval_i         (ic_inval),
      .req_valid_i     (ireq_valid),
      .req_ready_o     (ireq_ready),
      .req_addr_i      (ireq_addr),
      .rsp_valid_o     (irsp_valid),
      .rsp_rdata_o     (irsp_rdata),
      .bus_req_valid_o (ib_valid),
      .bus_req_ready_i (ib_ready),
      .bus_req_addr_o  (ib_addr),
      .bus_req_len_o   (ib_len),
      .bus_req_be_o    (ib_be),
      .bus_rsp_valid_i (ib_rsp_valid),
      .bus_rsp_rdata_i (bus_rsp_rdata_i),
      .bus_rsp_last_i  (bus_rsp_last_i)
  );

  muserisc_dcache #(
      .SETS(DC_SETS), .WAYS(DC_WAYS), .LINE_BYTES(LINE_BYTES),
      .C0_BASE(C0_BASE), .C0_SIZE(C0_SIZE),
      .C1_BASE(C1_BASE), .C1_SIZE(C1_SIZE)
  ) u_dcache (
      .clk_i           (clk_i),
      .rst_ni          (rst_ni),
      .cache_en_i      (cache_en_i),
      .req_valid_i     (dreq_valid),
      .req_ready_o     (dreq_ready),
      .req_addr_i      (dreq_addr),
      .req_op_i        (dreq_op),
      .req_wdata_i     (dreq_wdata),
      .req_be_i        (dreq_be),
      .rsp_valid_o     (drsp_valid),
      .rsp_rdata_o     (drsp_rdata),
      .bus_req_valid_o (db_valid),
      .bus_req_ready_i (db_ready),
      .bus_req_addr_o  (db_addr),
      .bus_req_write_o (db_write),
      .bus_req_len_o   (db_len),
      .bus_req_wdata_o (db_wdata),
      .bus_req_be_o    (db_be),
      .bus_req_last_o  (db_last),
      .bus_rsp_valid_i (db_rsp_valid),
      .bus_rsp_rdata_i (bus_rsp_rdata_i),
      .bus_rsp_last_i  (bus_rsp_last_i)
  );

  muserisc_bus_arb u_arb (
      .clk_i          (clk_i),
      .rst_ni         (rst_ni),
      .m0_req_valid_i (ib_valid),
      .m0_req_ready_o (ib_ready),
      .m0_req_addr_i  (ib_addr),
      .m0_req_len_i   (ib_len),
      .m0_req_be_i    (ib_be),
      .m0_rsp_valid_o (ib_rsp_valid),
      .m1_req_valid_i (db_valid),
      .m1_req_ready_o (db_ready),
      .m1_req_addr_i  (db_addr),
      .m1_req_write_i (db_write),
      .m1_req_len_i   (db_len),
      .m1_req_wdata_i (db_wdata),
      .m1_req_be_i    (db_be),
      .m1_req_last_i  (db_last),
      .m1_rsp_valid_o (db_rsp_valid),
      .req_valid_o    (bus_req_valid_o),
      .req_ready_i    (bus_req_ready_i),
      .req_addr_o     (bus_req_addr_o),
      .req_write_o    (bus_req_write_o),
      .req_len_o      (bus_req_len_o),
      .req_wdata_o    (bus_req_wdata_o),
      .req_be_o       (bus_req_be_o),
      .req_last_o     (bus_req_last_o),
      .req_inst_o     (bus_req_inst_o),
      .rsp_valid_i    (bus_rsp_valid_i),
      .rsp_last_i     (bus_rsp_last_i)
  );
endmodule
`default_nettype wire
