// museRISC synthesizable SoC top (issue #4): in-house
// RV64 core with L1 I$/D$ (muserisc_cpu) + memory fabric +
// boot ROM + CLINT + PLIC + 16550 UART + muse_crypto
// accelerator. Memory map matches docs/SPEC.md,
// sw/linux/muserisc.dts, and the C++ model in
// tb/cpp/soc_tb.cpp:
//
//   0x0000_1000  boot ROM (4 KiB, muserisc_bootrom)
//   0x0200_0000  CLINT
//   0x0C00_0000  PLIC (UART = source 10, ext_irq_i ORed in)
//   0x1000_0000  16550 UART
//   0x2000_0000  crypto accelerator (AXI-Lite via bridge)
//   0x8000_0000  external RAM window (mem_* memory bus)
//
// External RAM is a memory-bus slave (valid/ready requests,
// line bursts, any latency; protocol in rtl/core/
// muserisc_cpu.sv), so a simulation model, an ASIC SRAM
// wrapper, or an FPGA BRAM/DDR (AXI4) bridge can serve it.
// Only the RAM window is cacheable (muserisc_cpu default PMA);
// the devices are reached by uncached single-beat accesses
// through muserisc_soc_fabric, so their side effects happen
// exactly once per load/store.
`default_nettype none
module muserisc_soc_top (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire [63:0] boot_pc_i,
    input  wire        cache_en_i,   // strap: 0 = L1 caches off
    // External RAM (memory-bus master).
    output wire        mem_req_valid_o,
    input  wire        mem_req_ready_i,
    output wire [63:0] mem_req_addr_o,
    output wire        mem_req_write_o,
    output wire [7:0]  mem_req_len_o,
    output wire [63:0] mem_req_wdata_o,
    output wire [7:0]  mem_req_be_o,
    output wire        mem_req_last_o,
    output wire        mem_req_inst_o,
    input  wire        mem_rsp_valid_i,
    input  wire [63:0] mem_rsp_rdata_i,
    input  wire        mem_rsp_last_i,
    // UART serial pins + parallel byte stream (host capture).
    output wire        uart_tx_o,
    input  wire        uart_rx_i,
    output wire [7:0]  uart_tx_data_o,
    output wire        uart_tx_valid_o,
    input  wire [7:0]  uart_rx_data_i,
    input  wire        uart_rx_valid_i,
    // Extra PLIC interrupt sources (source 10 is the UART).
    input  wire [31:0] ext_irq_i,
    // Trap observability (test/debug).
    output wire        trap_o,
    output wire [63:0] trap_cause_o,
    output wire [63:0] trap_pc_o
);
  localparam logic [63:0] ROM_BASE    = 64'h0000_1000;
  localparam logic [63:0] CLINT_BASE  = 64'h0200_0000;
  localparam logic [63:0] PLIC_BASE   = 64'h0C00_0000;
  localparam logic [63:0] UART_BASE   = 64'h1000_0000;
  localparam logic [63:0] CRYPTO_BASE = 64'h2000_0000;
  localparam logic [63:0] RAM_BASE    = 64'h8000_0000;

  function automatic logic in_range(
      input logic [63:0] a, input logic [63:0] base,
      input logic [63:0] size);
    return (a >= base) && ((a - base) < size);
  endfunction

  // CPU memory bus.
  logic        c_req_valid, c_req_ready, c_req_write, c_req_last;
  logic        c_req_inst, c_rsp_valid, c_rsp_last;
  logic [63:0] c_req_addr, c_req_wdata, c_rsp_rdata;
  logic [7:0]  c_req_len, c_req_be;
  logic        irq_m_timer, irq_m_soft, irq_m_ext, irq_s_ext;
  // Device port (from the fabric).
  logic        dev_sel, dev_re, crypto_stall;
  logic [63:0] dev_addr, dev_wdata, dev_rdata;
  logic [7:0]  dev_be;

  /* verilator lint_off UNUSEDSIGNAL */
  logic        dbg_st_valid;
  logic [63:0] dbg_st_addr, dbg_st_wdata, dbg_fetch_pa;
  logic [7:0]  dbg_st_be;
  /* verilator lint_on UNUSEDSIGNAL */

  muserisc_cpu u_cpu (
      .clk_i           (clk_i),
      .rst_ni          (rst_ni),
      .boot_pc_i       (boot_pc_i),
      .cache_en_i      (cache_en_i),
      .bus_req_valid_o (c_req_valid),
      .bus_req_ready_i (c_req_ready),
      .bus_req_addr_o  (c_req_addr),
      .bus_req_write_o (c_req_write),
      .bus_req_len_o   (c_req_len),
      .bus_req_wdata_o (c_req_wdata),
      .bus_req_be_o    (c_req_be),
      .bus_req_last_o  (c_req_last),
      .bus_req_inst_o  (c_req_inst),
      .bus_rsp_valid_i (c_rsp_valid),
      .bus_rsp_rdata_i (c_rsp_rdata),
      .bus_rsp_last_i  (c_rsp_last),
      .trap_o          (trap_o),
      .trap_cause_o    (trap_cause_o),
      .trap_pc_o       (trap_pc_o),
      .trap_halt_i     (1'b0),
      .irq_m_timer_i   (irq_m_timer),
      .irq_m_soft_i    (irq_m_soft),
      .irq_m_ext_i     (irq_m_ext),
      .irq_s_timer_i   (1'b0),
      .irq_s_ext_i     (irq_s_ext),
      .dbg_st_valid_o  (dbg_st_valid),
      .dbg_st_addr_o   (dbg_st_addr),
      .dbg_st_be_o     (dbg_st_be),
      .dbg_st_wdata_o  (dbg_st_wdata),
      .dbg_fetch_pa_o  (dbg_fetch_pa)
  );

  muserisc_soc_fabric #(.RAM_BASE(RAM_BASE)) u_fabric (
      .clk_i         (clk_i),
      .rst_ni        (rst_ni),
      .m_req_valid_i (c_req_valid),
      .m_req_ready_o (c_req_ready),
      .m_req_addr_i  (c_req_addr),
      .m_req_write_i (c_req_write),
      .m_req_len_i   (c_req_len),
      .m_req_wdata_i (c_req_wdata),
      .m_req_be_i    (c_req_be),
      .m_req_last_i  (c_req_last),
      .m_req_inst_i  (c_req_inst),
      .m_rsp_valid_o (c_rsp_valid),
      .m_rsp_rdata_o (c_rsp_rdata),
      .m_rsp_last_o  (c_rsp_last),
      .r_req_valid_o (mem_req_valid_o),
      .r_req_ready_i (mem_req_ready_i),
      .r_req_addr_o  (mem_req_addr_o),
      .r_req_write_o (mem_req_write_o),
      .r_req_len_o   (mem_req_len_o),
      .r_req_wdata_o (mem_req_wdata_o),
      .r_req_be_o    (mem_req_be_o),
      .r_req_last_o  (mem_req_last_o),
      .r_req_inst_o  (mem_req_inst_o),
      .r_rsp_valid_i (mem_rsp_valid_i),
      .r_rsp_rdata_i (mem_rsp_rdata_i),
      .r_rsp_last_i  (mem_rsp_last_i),
      .dev_sel_o     (dev_sel),
      .dev_addr_o    (dev_addr),
      .dev_re_o      (dev_re),
      .dev_be_o      (dev_be),
      .dev_wdata_o   (dev_wdata),
      .dev_rdata_i   (dev_rdata),
      .dev_stall_i   (crypto_stall)
  );

  // Device decode (the fabric presents one access at a time).
  logic sel_rom, sel_clint, sel_plic, sel_uart, sel_crypto;
  assign sel_rom = in_range(dev_addr, ROM_BASE, 64'h1000);
  assign sel_clint = in_range(dev_addr, CLINT_BASE, 64'h1_0000);
  assign sel_plic = in_range(dev_addr, PLIC_BASE, 64'h400_0000);
  assign sel_uart = in_range(dev_addr, UART_BASE, 64'h100);
  assign sel_crypto = in_range(dev_addr, CRYPTO_BASE, 64'h100);

  logic [63:0] rom_data, clint_rdata, plic_rdata, uart_rdata;
  logic [63:0] crypto_rdata;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] rom32_unused;
  /* verilator lint_on UNUSEDSIGNAL */
  muserisc_bootrom u_rom (
      .addr_i(dev_addr[11:0]), .data_o(rom32_unused),
      .data64_o(rom_data));

  always_comb begin
    if (sel_rom) dev_rdata = rom_data;
    else if (sel_clint) dev_rdata = clint_rdata;
    else if (sel_plic) dev_rdata = plic_rdata;
    else if (sel_uart) dev_rdata = uart_rdata;
    else if (sel_crypto) dev_rdata = crypto_rdata;
    else dev_rdata = 64'd0;
  end

  logic uart_irq;
  logic [31:0] plic_sources;
  logic [1:0]  plic_eip;
  assign plic_sources = ext_irq_i | {21'd0, uart_irq, 10'd0};
  assign irq_m_ext = plic_eip[0];
  assign irq_s_ext = plic_eip[1];

  muserisc_clint u_clint (
      .clk_i(clk_i), .rst_ni(rst_ni),
      .addr_i(dev_addr[15:0]),
      .be_i(sel_clint ? dev_be : 8'd0),
      .wdata_i(dev_wdata), .rdata_o(clint_rdata),
      .irq_m_timer_o(irq_m_timer), .irq_m_soft_o(irq_m_soft));
  muserisc_plic u_plic (
      .clk_i(clk_i), .rst_ni(rst_ni),
      .addr_i(dev_addr[25:0]),
      .re_i(sel_plic && dev_re),
      .be_i(sel_plic ? dev_be : 8'd0),
      .wdata_i(dev_wdata), .rdata_o(plic_rdata),
      .irq_sources_i(plic_sources), .eip_o(plic_eip));
  muserisc_uart16550 u_uart (
      .clk_i(clk_i), .rst_ni(rst_ni),
      .addr_i(dev_addr[2:0]),
      .re_i(sel_uart && dev_re),
      .be_i(sel_uart ? dev_be : 8'd0),
      .wdata_i(dev_wdata), .rdata_o(uart_rdata),
      .irq_o(uart_irq), .tx_o(uart_tx_o), .rx_i(uart_rx_i),
      .tx_data_o(uart_tx_data_o), .tx_valid_o(uart_tx_valid_o),
      .rx_data_i(uart_rx_data_i), .rx_valid_i(uart_rx_valid_i));
  muserisc_crypto_bridge u_crypto_bridge (
      .clk_i(clk_i), .rst_ni(rst_ni),
      .sel_i(sel_crypto && dev_sel), .re_i(dev_re),
      .be_i(dev_be), .addr_i(dev_addr[7:0]),
      .wdata_i(dev_wdata), .rdata_o(crypto_rdata),
      .stall_o(crypto_stall));
endmodule
`default_nettype wire
