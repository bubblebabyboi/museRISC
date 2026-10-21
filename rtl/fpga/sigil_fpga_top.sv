// Sigil FPGA SoC top (issue #52, FPGA F1; plan in docs/FPGA_F2.md).
// The unit the AWS F2 Custom Logic wrapper (#54) instantiates:
//
//   sigil_soc_top (core + L1s + boot ROM + CLINT + PLIC + 16550 +
//   crypto, unchanged memory map / sw/linux/sigil.dts)
//     mem_* (RAM window 0x8000_0000) -> sigil_mbus_axi4 -> m_axi_*
//   + boot/control: SoC reset hold, boot PC, cache strap, a free-
//     running cycle counter, status
//   + virtual UART: the 16550's byte stream through a TX FIFO
//     (SoC -> host) and an RX FIFO (host -> SoC), as plain FIFO
//     ports for #54 to map onto OCL AXI-Lite registers.
//
// Clocking: one clock domain. clk_i clocks the SoC, the bridge
// and the AXI4 master, so #54 must run the Shell DDR4 AXI port
// (or an AXI clock converter in front of it) on the same clock
// as the core: clk_main_a0 directly if the core closes timing at
// 250 MHz, otherwise an AWS_CLK_GEN clock plus an AXI clock
// converter in the CL. Control/UART ports are also on clk_i; #54
// owns any OCL-side CDC.
//
// Reset: rst_ni (the Shell reset for this clock domain, active
// low) is synchronized here (asynchronous assert, release two
// edges after it rises) and resets the bridge, FIFOs, counter and
// control logic. The SoC is held in reset while soc_reset_req_i
// is 1 -- #54's OCL control register should reset to 1 so the
// host can load DDR first. Asserting soc_reset_req_i while the
// SoC runs first quiesces the bridge (no new memory requests)
// and waits for the transaction in flight to finish, then resets
// the SoC; the AXI side therefore never sees a torn burst and
// needs no reset of its own. soc_in_reset_o reports the state.
// The SoC's own reset synchronizer adds two more cycles before
// the core runs; UART RX bytes are held off for RX_HOLDOFF cycles
// after release so none land in a UART still in reset.
//
// Virtual UART: every byte the SoC writes to the 16550 THR is
// pushed into the TX FIFO (uart_tx_*); if it is full the byte is
// dropped and uart_tx_overflow_o sets (cleared by the next SoC
// reset). The 16550 paces the CPU at one byte per 160*divisor
// clocks (its serial shifter still runs), so a host draining a
// 1 KiB FIFO every few hundred microseconds keeps up at 100 MHz.
// Host bytes pushed into the RX FIFO (uart_rx_*) are fed to the
// 16550 RX FIFO whenever it has room, so none are lost. A SoC
// reset requested while running discards RX bytes not yet taken
// (the RX FIFO is flushed as the SoC enters reset); bytes pushed
// while the SoC is held are kept and delivered after release.
// The TX FIFO is never flushed: the host drains what is left.
`default_nettype none
module sigil_fpga_top #(
    // SoC L1 geometry (sigil_soc_top defaults).
    parameter int unsigned IC_SETS = 64,
    parameter int unsigned IC_WAYS = 2,
    parameter int unsigned DC_SETS = 64,
    parameter int unsigned DC_WAYS = 4,
    // AXI4 master towards DDR. F2 Shell DDR4: 512-bit data.
    parameter int unsigned AXI_ID_W   = 16,
    parameter int unsigned AXI_ADDR_W = 64,
    parameter int unsigned AXI_DATA_W = 64,
    parameter logic [AXI_ID_W-1:0] AXI_ID = '0,
    // SoC RAM window [0x8000_0000, +RAM_SIZE) -> DDR [DDR_BASE, +RAM_SIZE).
    // RAM_SIZE must match the DTS memory node (128 MiB).
    parameter logic [63:0] RAM_SIZE = 64'h0000_0000_0800_0000,
    parameter logic [63:0] DDR_BASE = 64'h0,
    // Virtual UART FIFO depths (powers of two).
    parameter int unsigned UART_TX_DEPTH = 1024,
    parameter int unsigned UART_RX_DEPTH = 64,
    parameter int unsigned RX_HOLDOFF = 8
) (
    input  wire        clk_i,
    input  wire        rst_ni,
    // Boot / control (from #54's OCL registers).
    input  wire        soc_reset_req_i,   // 1 = hold the SoC in reset
    input  wire [63:0] boot_pc_i,         // reset PC (0x1000 = boot ROM)
    input  wire        cache_en_i,        // L1 strap, sampled while in reset
    output logic       soc_in_reset_o,
    output logic [63:0] cycle_count_o,    // clk_i cycles since rst_ni release
    output logic       mem_err_o,         // sticky AXI error (SLVERR/DECERR/ID)
    output logic       trap_o,            // core trap pulse (debug)
    output logic [63:0] trap_cause_o,
    output logic [63:0] trap_pc_o,
    // Virtual UART TX (SoC -> host), first-word fall-through.
    output logic [7:0] uart_tx_data_o,
    output logic       uart_tx_valid_o,   // FIFO not empty
    input  wire        uart_tx_pop_i,     // take uart_tx_data_o
    output logic [$clog2(UART_TX_DEPTH):0] uart_tx_count_o,
    output logic       uart_tx_overflow_o,
    // Virtual UART RX (host -> SoC).
    input  wire [7:0]  uart_rx_data_i,
    input  wire        uart_rx_push_i,    // ignored when uart_rx_full_o
    output logic       uart_rx_full_o,
    output logic [$clog2(UART_RX_DEPTH):0] uart_rx_count_o,
    // AXI4 master (DDR).
    output logic [AXI_ID_W-1:0]     m_axi_awid,
    output logic [AXI_ADDR_W-1:0]   m_axi_awaddr,
    output logic [7:0]              m_axi_awlen,
    output logic [2:0]              m_axi_awsize,
    output logic [1:0]              m_axi_awburst,
    output logic                    m_axi_awlock,
    output logic [3:0]              m_axi_awcache,
    output logic [2:0]              m_axi_awprot,
    output logic [3:0]              m_axi_awqos,
    output logic                    m_axi_awvalid,
    input  wire                     m_axi_awready,
    output logic [AXI_DATA_W-1:0]   m_axi_wdata,
    output logic [AXI_DATA_W/8-1:0] m_axi_wstrb,
    output logic                    m_axi_wlast,
    output logic                    m_axi_wvalid,
    input  wire                     m_axi_wready,
    input  wire [AXI_ID_W-1:0]      m_axi_bid,
    input  wire [1:0]               m_axi_bresp,
    input  wire                     m_axi_bvalid,
    output logic                    m_axi_bready,
    output logic [AXI_ID_W-1:0]     m_axi_arid,
    output logic [AXI_ADDR_W-1:0]   m_axi_araddr,
    output logic [7:0]              m_axi_arlen,
    output logic [2:0]              m_axi_arsize,
    output logic [1:0]              m_axi_arburst,
    output logic                    m_axi_arlock,
    output logic [3:0]              m_axi_arcache,
    output logic [2:0]              m_axi_arprot,
    output logic [3:0]              m_axi_arqos,
    output logic                    m_axi_arvalid,
    input  wire                     m_axi_arready,
    input  wire [AXI_ID_W-1:0]      m_axi_rid,
    input  wire [AXI_DATA_W-1:0]    m_axi_rdata,
    input  wire [1:0]               m_axi_rresp,
    input  wire                     m_axi_rlast,
    input  wire                     m_axi_rvalid,
    output logic                    m_axi_rready
);
  localparam logic [63:0] RAM_BASE = 64'h0000_0000_8000_0000;

  // Reset synchronizer for the FPGA-side logic (same structure as
  // sigil_soc_top's: the released reset is never a flop data input).
  logic rst_meta_q, rst_sync_q, rst_n;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rst_meta_q <= 1'b0;
      rst_sync_q <= 1'b0;
    end else begin
      rst_meta_q <= 1'b1;
      rst_sync_q <= rst_meta_q;
    end
  end
  assign rst_n = rst_sync_q;

  // SoC reset sequencing: RUN -> (request) QUIESCE -> (bridge idle)
  // HOLD -> (request released) RUN. Starts in HOLD.
  typedef enum logic [1:0] {C_HOLD, C_RUN, C_QUIESCE} cstate_e;
  cstate_e cst_q;
  logic    soc_rst_n_q;   // drives only sigil_soc_top.rst_ni
  logic    br_idle;
  logic [$clog2(RX_HOLDOFF + 1)-1:0] holdoff_q;
  logic [63:0] cycle_q;
  logic        rx_flush_q;  // one cycle as the SoC enters reset

  always_ff @(posedge clk_i or negedge rst_n) begin
    if (!rst_n) begin
      cst_q <= C_HOLD;
      soc_rst_n_q <= 1'b0;
      holdoff_q <= '0;
      cycle_q <= 64'd0;
      rx_flush_q <= 1'b0;
    end else begin
      cycle_q <= cycle_q + 64'd1;
      rx_flush_q <= 1'b0;
      unique case (cst_q)
        C_RUN: if (soc_reset_req_i) cst_q <= C_QUIESCE;
        C_QUIESCE: if (br_idle) begin
          cst_q <= C_HOLD;
          soc_rst_n_q <= 1'b0;
          rx_flush_q <= 1'b1;
        end
        default: if (!soc_reset_req_i) begin  // C_HOLD
          cst_q <= C_RUN;
          soc_rst_n_q <= 1'b1;
        end
      endcase
      if (cst_q != C_RUN) holdoff_q <= '0;
      else if (holdoff_q != ($clog2(RX_HOLDOFF + 1))'(RX_HOLDOFF))
        holdoff_q <= holdoff_q + 1'b1;
    end
  end
  assign soc_in_reset_o = (cst_q == C_HOLD);
  assign cycle_count_o = cycle_q;

  // SoC.
  logic        mem_req_valid, mem_req_ready, mem_req_write, mem_req_last;
  logic        mem_req_inst, mem_rsp_valid, mem_rsp_last;
  logic [63:0] mem_req_addr, mem_req_wdata, mem_rsp_rdata;
  logic [7:0]  mem_req_len, mem_req_be;
  logic [7:0]  soc_tx_data, rxf_data;
  logic        soc_tx_valid, soc_rx_ready, soc_rx_valid, rxf_empty;
  /* verilator lint_off UNUSEDSIGNAL */
  logic        uart_tx_serial;
  /* verilator lint_on UNUSEDSIGNAL */

  sigil_soc_top #(
      .IC_SETS(IC_SETS), .IC_WAYS(IC_WAYS),
      .DC_SETS(DC_SETS), .DC_WAYS(DC_WAYS)
  ) u_soc (
      .clk_i           (clk_i),
      .rst_ni          (soc_rst_n_q),
      .boot_pc_i       (boot_pc_i),
      .cache_en_i      (cache_en_i),
      .mem_req_valid_o (mem_req_valid),
      .mem_req_ready_i (mem_req_ready),
      .mem_req_addr_o  (mem_req_addr),
      .mem_req_write_o (mem_req_write),
      .mem_req_len_o   (mem_req_len),
      .mem_req_wdata_o (mem_req_wdata),
      .mem_req_be_o    (mem_req_be),
      .mem_req_last_o  (mem_req_last),
      .mem_req_inst_o  (mem_req_inst),
      .mem_rsp_valid_i (mem_rsp_valid),
      .mem_rsp_rdata_i (mem_rsp_rdata),
      .mem_rsp_last_i  (mem_rsp_last),
      .uart_tx_o       (uart_tx_serial),
      .uart_rx_i       (1'b1),
      .uart_tx_data_o  (soc_tx_data),
      .uart_tx_valid_o (soc_tx_valid),
      .uart_rx_data_i  (rxf_data),
      .uart_rx_valid_i (soc_rx_valid),
      .uart_rx_ready_o (soc_rx_ready),
      .ext_irq_i       (32'd0),
      .trap_o          (trap_o),
      .trap_cause_o    (trap_cause_o),
      .trap_pc_o       (trap_pc_o)
  );

  sigil_mbus_axi4 #(
      .AXI_ID_W(AXI_ID_W), .AXI_ADDR_W(AXI_ADDR_W),
      .AXI_DATA_W(AXI_DATA_W), .AXI_ID(AXI_ID),
      .MEM_BASE(RAM_BASE), .MEM_MASK(RAM_SIZE - 64'd1),
      .AXI_BASE(DDR_BASE)
  ) u_bridge (
      .clk_i         (clk_i),
      .rst_ni        (rst_n),
      .quiesce_i     (cst_q != C_RUN),
      .idle_o        (br_idle),
      .err_o         (mem_err_o),
      .req_valid_i   (mem_req_valid),
      .req_ready_o   (mem_req_ready),
      .req_addr_i    (mem_req_addr),
      .req_write_i   (mem_req_write),
      .req_len_i     (mem_req_len),
      .req_wdata_i   (mem_req_wdata),
      .req_be_i      (mem_req_be),
      .req_last_i    (mem_req_last),
      .req_inst_i    (mem_req_inst),
      .rsp_valid_o   (mem_rsp_valid),
      .rsp_rdata_o   (mem_rsp_rdata),
      .rsp_last_o    (mem_rsp_last),
      .m_axi_awid    (m_axi_awid),
      .m_axi_awaddr  (m_axi_awaddr),
      .m_axi_awlen   (m_axi_awlen),
      .m_axi_awsize  (m_axi_awsize),
      .m_axi_awburst (m_axi_awburst),
      .m_axi_awlock  (m_axi_awlock),
      .m_axi_awcache (m_axi_awcache),
      .m_axi_awprot  (m_axi_awprot),
      .m_axi_awqos   (m_axi_awqos),
      .m_axi_awvalid (m_axi_awvalid),
      .m_axi_awready (m_axi_awready),
      .m_axi_wdata   (m_axi_wdata),
      .m_axi_wstrb   (m_axi_wstrb),
      .m_axi_wlast   (m_axi_wlast),
      .m_axi_wvalid  (m_axi_wvalid),
      .m_axi_wready  (m_axi_wready),
      .m_axi_bid     (m_axi_bid),
      .m_axi_bresp   (m_axi_bresp),
      .m_axi_bvalid  (m_axi_bvalid),
      .m_axi_bready  (m_axi_bready),
      .m_axi_arid    (m_axi_arid),
      .m_axi_araddr  (m_axi_araddr),
      .m_axi_arlen   (m_axi_arlen),
      .m_axi_arsize  (m_axi_arsize),
      .m_axi_arburst (m_axi_arburst),
      .m_axi_arlock  (m_axi_arlock),
      .m_axi_arcache (m_axi_arcache),
      .m_axi_arprot  (m_axi_arprot),
      .m_axi_arqos   (m_axi_arqos),
      .m_axi_arvalid (m_axi_arvalid),
      .m_axi_arready (m_axi_arready),
      .m_axi_rid     (m_axi_rid),
      .m_axi_rdata   (m_axi_rdata),
      .m_axi_rresp   (m_axi_rresp),
      .m_axi_rlast   (m_axi_rlast),
      .m_axi_rvalid  (m_axi_rvalid),
      .m_axi_rready  (m_axi_rready)
  );

  // Virtual UART TX: SoC THR writes -> FIFO -> host.
  logic txf_full, txf_empty, tx_ovf_q;
  sigil_fifo #(.WIDTH(8), .DEPTH(UART_TX_DEPTH)) u_txf (
      .clk_i(clk_i), .rst_ni(rst_n), .flush_i(1'b0),
      .push_i(soc_tx_valid), .data_i(soc_tx_data), .full_o(txf_full),
      .pop_i(uart_tx_pop_i), .data_o(uart_tx_data_o),
      .empty_o(txf_empty), .count_o(uart_tx_count_o));
  assign uart_tx_valid_o = !txf_empty;
  always_ff @(posedge clk_i or negedge rst_n) begin
    if (!rst_n) tx_ovf_q <= 1'b0;
    else if (cst_q == C_HOLD) tx_ovf_q <= 1'b0;
    else if (soc_tx_valid && txf_full) tx_ovf_q <= 1'b1;
  end
  assign uart_tx_overflow_o = tx_ovf_q;

  // Virtual UART RX: host -> FIFO -> 16550 RX FIFO (when it has room).
  logic rx_feed;
  assign rx_feed = (cst_q == C_RUN) &&
                   (holdoff_q == ($clog2(RX_HOLDOFF + 1))'(RX_HOLDOFF)) &&
                   !rxf_empty;
  assign soc_rx_valid = rx_feed;
  sigil_fifo #(.WIDTH(8), .DEPTH(UART_RX_DEPTH)) u_rxf (
      .clk_i(clk_i), .rst_ni(rst_n), .flush_i(rx_flush_q),
      .push_i(uart_rx_push_i), .data_i(uart_rx_data_i),
      .full_o(uart_rx_full_o),
      .pop_i(rx_feed && soc_rx_ready), .data_o(rxf_data),
      .empty_o(rxf_empty), .count_o(uart_rx_count_o));
endmodule
`default_nettype wire
