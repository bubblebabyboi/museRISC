// Core-clock half of the AWS F2 Custom Logic (issue #54, FPGA F3):
// sigil_fpga_top (SoC + mbus->AXI4 bridge + virtual UART FIFOs)
// plus the OCL register block (sigil_ocl_regs) that exposes its
// control / status / cycle counter / UART ports as AXI4-Lite
// registers. Everything here is on clk_i (the AWS_CLK_GEN core
// clock); fpga/cl_sigil/design/cl_sigil.sv adds the clock domain
// crossings to the Shell (AXI4-Lite clock converter on the OCL
// side, AXI4 clock converter on the DDR side) and the Shell glue.
// Kept free of Xilinx primitives so Verilator lints and simulates
// it (tb/cpp/fpga_ocl_tb.cpp drives it the way fpga/host/ does).
// RAM_SIZE is the SoC RAM window (128 MiB in simulation, 80 GiB =
// DDR4 + HBM in the F2 CL); HBM_PRESENT / hbm_ready_i report the HBM.
`default_nettype none
module sigil_fpga_ocl #(
    parameter int unsigned AXI_ID_W   = 16,
    parameter int unsigned AXI_ADDR_W = 64,
    parameter int unsigned AXI_DATA_W = 512,
    parameter logic [AXI_ID_W-1:0] AXI_ID = '0,
    parameter logic [63:0] RAM_SIZE = 64'h0000_0000_0800_0000,
    parameter logic [63:0] DDR_BASE = 64'h0,
    parameter int unsigned UART_TX_DEPTH = 1024,
    parameter int unsigned UART_RX_DEPTH = 64,
    parameter logic [31:0] CORE_CLK_KHZ = 32'd62500,
    parameter bit          HBM_PRESENT = 1'b0
) (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        ddr_ready_i,       // synchronized to clk_i
    input  wire        hbm_ready_i,       // synchronized to clk_i
    output logic       soc_in_reset_o,    // status (virtual LEDs)
    output logic       mem_err_o,
    // AXI4-Lite slave (OCL registers).
    input  wire [31:0] s_axil_awaddr,
    input  wire        s_axil_awvalid,
    output logic       s_axil_awready,
    input  wire [31:0] s_axil_wdata,
    input  wire        s_axil_wvalid,
    output logic       s_axil_wready,
    output logic [1:0] s_axil_bresp,
    output logic       s_axil_bvalid,
    input  wire        s_axil_bready,
    input  wire [31:0] s_axil_araddr,
    input  wire        s_axil_arvalid,
    output logic       s_axil_arready,
    output logic [31:0] s_axil_rdata,
    output logic [1:0] s_axil_rresp,
    output logic       s_axil_rvalid,
    input  wire        s_axil_rready,
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
  localparam int unsigned TX_CW = $clog2(UART_TX_DEPTH) + 1;
  localparam int unsigned RX_CW = $clog2(UART_RX_DEPTH) + 1;
  localparam logic [63:0] RAM_MB = RAM_SIZE >> 20;

  logic        soc_reset_req, cache_en, soc_in_reset, trap;
  logic [63:0] boot_pc, cycle_count, trap_cause, trap_pc;
  logic [7:0]  tx_data, rx_data;
  logic        tx_valid, tx_pop, tx_ovf, rx_push, rx_full;
  logic [TX_CW-1:0] tx_count;
  logic [RX_CW-1:0] rx_count;
  logic        tx_drop, err_clr, fin_event, rtc_set;
  logic [63:0] err_addr, rtc_set_ns, rtc_ns;
  logic [31:0] err_info, err_count, fin_value, rtc_inc;
  logic        eng_start, eng_busy, eng_done, eng_fail;
  logic [1:0]  eng_mode;
  logic [63:0] eng_base, eng_size, eng_seed, eng_fail_addr, eng_cycles;
  logic [31:0] eng_mism, eng_rerr;

  assign soc_in_reset_o = soc_in_reset;

  sigil_ocl_regs #(
      .CORE_CLK_KHZ(CORE_CLK_KHZ), .TX_CW(TX_CW), .RX_CW(RX_CW),
      .RAM_SIZE_MB(RAM_MB[31:0]), .HBM_PRESENT(HBM_PRESENT)
  ) u_regs (
      .clk_i, .rst_ni,
      .s_axil_awaddr, .s_axil_awvalid, .s_axil_awready,
      .s_axil_wdata, .s_axil_wvalid, .s_axil_wready,
      .s_axil_bresp, .s_axil_bvalid, .s_axil_bready,
      .s_axil_araddr, .s_axil_arvalid, .s_axil_arready,
      .s_axil_rdata, .s_axil_rresp, .s_axil_rvalid, .s_axil_rready,
      .soc_reset_req_o   (soc_reset_req),
      .boot_pc_o         (boot_pc),
      .cache_en_o        (cache_en),
      .soc_in_reset_i    (soc_in_reset),
      .cycle_count_i     (cycle_count),
      .mem_err_i         (mem_err_o),
      .trap_i            (trap),
      .trap_cause_i      (trap_cause),
      .trap_pc_i         (trap_pc),
      .uart_tx_data_i    (tx_data),
      .uart_tx_valid_i   (tx_valid),
      .uart_tx_pop_o     (tx_pop),
      .uart_tx_count_i   (tx_count),
      .uart_tx_overflow_i(tx_ovf),
      .uart_rx_data_o    (rx_data),
      .uart_rx_push_o    (rx_push),
      .uart_rx_full_i    (rx_full),
      .uart_rx_count_i   (rx_count),
      .uart_tx_drop_o    (tx_drop),
      .ddr_ready_i,
      .hbm_ready_i,
      .err_clr_o         (err_clr),
      .err_addr_i        (err_addr),
      .err_info_i        (err_info),
      .err_count_i       (err_count),
      .fin_event_i       (fin_event),
      .fin_value_i       (fin_value),
      .rtc_set_o         (rtc_set),
      .rtc_set_ns_o      (rtc_set_ns),
      .rtc_inc_o         (rtc_inc),
      .rtc_ns_i          (rtc_ns),
      .eng_start_o       (eng_start),
      .eng_mode_o        (eng_mode),
      .eng_base_o        (eng_base),
      .eng_size_o        (eng_size),
      .eng_seed_o        (eng_seed),
      .eng_busy_i        (eng_busy),
      .eng_done_i        (eng_done),
      .eng_fail_i        (eng_fail),
      .eng_mism_i        (eng_mism),
      .eng_fail_addr_i   (eng_fail_addr),
      .eng_rerr_i        (eng_rerr),
      .eng_cycles_i      (eng_cycles)
  );

  sigil_fpga_top #(
      .AXI_ID_W(AXI_ID_W), .AXI_ADDR_W(AXI_ADDR_W),
      .AXI_DATA_W(AXI_DATA_W), .AXI_ID(AXI_ID),
      .RAM_SIZE(RAM_SIZE), .DDR_BASE(DDR_BASE),
      .UART_TX_DEPTH(UART_TX_DEPTH), .UART_RX_DEPTH(UART_RX_DEPTH)
  ) u_top (
      .clk_i, .rst_ni,
      .soc_reset_req_i   (soc_reset_req),
      .boot_pc_i         (boot_pc),
      .cache_en_i        (cache_en),
      .soc_in_reset_o    (soc_in_reset),
      .cycle_count_o     (cycle_count),
      .mem_err_o,
      .err_clr_i         (err_clr),
      .err_addr_o        (err_addr),
      .err_info_o        (err_info),
      .err_count_o       (err_count),
      .trap_o            (trap),
      .trap_cause_o      (trap_cause),
      .trap_pc_o         (trap_pc),
      .uart_tx_data_o    (tx_data),
      .uart_tx_valid_o   (tx_valid),
      .uart_tx_pop_i     (tx_pop),
      .uart_tx_count_o   (tx_count),
      .uart_tx_overflow_o(tx_ovf),
      .uart_tx_drop_i    (tx_drop),
      .uart_rx_data_i    (rx_data),
      .uart_rx_push_i    (rx_push),
      .uart_rx_full_o    (rx_full),
      .uart_rx_count_o   (rx_count),
      .fin_event_o       (fin_event),
      .fin_value_o       (fin_value),
      .rtc_set_i         (rtc_set),
      .rtc_set_ns_i      (rtc_set_ns),
      .rtc_inc_i         (rtc_inc),
      .rtc_ns_o          (rtc_ns),
      .eng_start_i       (eng_start),
      .eng_mode_i        (eng_mode),
      .eng_base_i        (eng_base),
      .eng_size_i        (eng_size),
      .eng_seed_i        (eng_seed),
      .eng_busy_o        (eng_busy),
      .eng_done_o        (eng_done),
      .eng_fail_o        (eng_fail),
      .eng_mism_o        (eng_mism),
      .eng_fail_addr_o   (eng_fail_addr),
      .eng_rerr_o        (eng_rerr),
      .eng_cycles_o      (eng_cycles),
      .m_axi_awid, .m_axi_awaddr, .m_axi_awlen, .m_axi_awsize,
      .m_axi_awburst, .m_axi_awlock, .m_axi_awcache, .m_axi_awprot,
      .m_axi_awqos, .m_axi_awvalid, .m_axi_awready,
      .m_axi_wdata, .m_axi_wstrb, .m_axi_wlast, .m_axi_wvalid,
      .m_axi_wready,
      .m_axi_bid, .m_axi_bresp, .m_axi_bvalid, .m_axi_bready,
      .m_axi_arid, .m_axi_araddr, .m_axi_arlen, .m_axi_arsize,
      .m_axi_arburst, .m_axi_arlock, .m_axi_arcache, .m_axi_arprot,
      .m_axi_arqos, .m_axi_arvalid, .m_axi_arready,
      .m_axi_rid, .m_axi_rdata, .m_axi_rresp, .m_axi_rlast,
      .m_axi_rvalid, .m_axi_rready
  );
endmodule
`default_nettype wire
