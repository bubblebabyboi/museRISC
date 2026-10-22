// OCL AXI-Lite register block for the AWS F2 Custom Logic (issue #54,
// FPGA F3; register map in docs/FPGA_F2.md "F3"). Maps the
// sigil_fpga_top control / status / cycle-counter / virtual-UART
// ports onto 32-bit registers that the host runtime (fpga/host/)
// reaches through the Shell OCL BAR (AppPF BAR0).
//
// Clocking: everything here runs on the SoC core clock. The CL puts
// an AXI-Lite clock converter between the Shell OCL port
// (clk_main_a0) and s_axil_*, so this block needs no CDC of its own.
//
// Protocol: AXI4-Lite slave, one transaction of each kind at a
// time; 32-bit accesses only (WSTRB is ignored), always OKAY.
// Unmapped reads return 0xBAAD_DEC0, unmapped writes are dropped.
// Read side effects (documented per register): UART_TX_DATA pops
// the TX FIFO, UART_TX_DATA3 pops up to three bytes (the read takes
// a few more core cycles), CYCLE_LO / RTC_LO snapshot the upper half
// into CYCLE_HI / RTC_HI. Writing UART_RX_DATA pushes one byte
// (dropped when the RX FIFO is full; RX_STATUS.full tells the host to
// wait). Version 4 (issues #62, #63, #65-#67) adds the HBM status,
// bridge error capture, test finisher, RTC, memory engine and
// multi-byte UART drain registers (docs/FPGA_F2.md register map).
//
// Reset (rst_ni, active low, synchronous to clk_i's domain): CTRL
// comes up with soc_reset_req = 1 and cache_en = 1, BOOT_PC with
// 0x1000 (boot ROM), so the SoC stays held until the host has
// loaded DDR and cleared CTRL.soc_reset_req.
`default_nettype none
module sigil_ocl_regs #(
    // Nominal core clock in kHz (from the build's clock recipe),
    // readable as CLK_KHZ; the host compares it with the measured
    // cycle-counter rate.
    parameter logic [31:0] CORE_CLK_KHZ = 32'd62500,
    parameter int unsigned TX_CW = 11,   // $clog2(UART_TX_DEPTH)+1
    parameter int unsigned RX_CW = 7,    // $clog2(UART_RX_DEPTH)+1
    // RAM window of the build (RAM_SIZE_MB register) and HBM presence.
    parameter logic [31:0] RAM_SIZE_MB = 32'd128,
    parameter bit          HBM_PRESENT = 1'b0
) (
    input  wire        clk_i,
    input  wire        rst_ni,
    // AXI4-Lite slave (from the OCL clock converter).
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
    // To / from sigil_fpga_top.
    output logic       soc_reset_req_o,
    output logic [63:0] boot_pc_o,
    output logic       cache_en_o,
    input  wire        soc_in_reset_i,
    input  wire [63:0] cycle_count_i,
    input  wire        mem_err_i,
    input  wire        trap_i,
    input  wire [63:0] trap_cause_i,
    input  wire [63:0] trap_pc_i,
    input  wire [7:0]  uart_tx_data_i,
    input  wire        uart_tx_valid_i,
    output logic       uart_tx_pop_o,
    input  wire [TX_CW-1:0] uart_tx_count_i,
    input  wire        uart_tx_overflow_i,
    output logic [7:0] uart_rx_data_o,
    output logic       uart_rx_push_o,
    input  wire        uart_rx_full_i,
    input  wire [RX_CW-1:0] uart_rx_count_i,
    output logic       uart_tx_drop_o,
    // Shell DDR4 calibrated / HBM initialized (synchronized to clk_i).
    input  wire        ddr_ready_i,
    input  wire        hbm_ready_i,
    // Bridge error capture (#62).
    output logic       err_clr_o,
    input  wire [63:0] err_addr_i,
    input  wire [31:0] err_info_i,
    input  wire [31:0] err_count_i,
    // Test finisher and RTC (#67).
    input  wire        fin_event_i,
    input  wire [31:0] fin_value_i,
    output logic       rtc_set_o,
    output logic [63:0] rtc_set_ns_o,
    output logic [31:0] rtc_inc_o,
    input  wire [63:0] rtc_ns_i,
    // Memory engine.
    output logic       eng_start_o,
    output logic [1:0] eng_mode_o,
    output logic [63:0] eng_base_o,
    output logic [63:0] eng_size_o,
    output logic [63:0] eng_seed_o,
    input  wire        eng_busy_i,
    input  wire        eng_done_i,
    input  wire        eng_fail_i,
    input  wire [31:0] eng_mism_i,
    input  wire [63:0] eng_fail_addr_i,
    input  wire [31:0] eng_rerr_i,
    input  wire [63:0] eng_cycles_i
);
  // Register offsets (byte addresses within the OCL BAR).
  localparam logic [11:0] A_ID          = 12'h000;  // RO "SIGL"
  localparam logic [11:0] A_VERSION     = 12'h004;  // RO
  localparam logic [11:0] A_CTRL        = 12'h008;  // RW
  localparam logic [11:0] A_STATUS      = 12'h00C;  // RO
  localparam logic [11:0] A_BOOT_PC_LO  = 12'h010;  // RW
  localparam logic [11:0] A_BOOT_PC_HI  = 12'h014;  // RW
  localparam logic [11:0] A_CYCLE_LO    = 12'h018;  // RO, snapshots HI
  localparam logic [11:0] A_CYCLE_HI    = 12'h01C;  // RO (snapshot)
  localparam logic [11:0] A_TRAP_COUNT  = 12'h020;  // RO
  localparam logic [11:0] A_CLK_KHZ     = 12'h024;  // RO
  localparam logic [11:0] A_TRAP_CAUSE_LO = 12'h028;
  localparam logic [11:0] A_TRAP_CAUSE_HI = 12'h02C;
  localparam logic [11:0] A_TRAP_PC_LO  = 12'h030;
  localparam logic [11:0] A_TRAP_PC_HI  = 12'h034;
  localparam logic [11:0] A_HOST_FLAGS  = 12'h038;  // RW (CL reset only)
  localparam logic [11:0] A_SCRATCH     = 12'h03C;  // RW
  localparam logic [11:0] A_TX_DATA     = 12'h040;  // RO, pops
  localparam logic [11:0] A_TX_STATUS   = 12'h044;  // RO
  localparam logic [11:0] A_RX_DATA     = 12'h048;  // WO, pushes
  localparam logic [11:0] A_RX_STATUS   = 12'h04C;  // RO
  localparam logic [11:0] A_TX_DATA3    = 12'h050;  // RO, pops up to 3
  localparam logic [11:0] A_RAM_SIZE_MB = 12'h054;  // RO
  localparam logic [11:0] A_CAPS        = 12'h058;  // RO
  localparam logic [11:0] A_ERR_ADDR_LO = 12'h060;  // RO
  localparam logic [11:0] A_ERR_ADDR_HI = 12'h064;  // RO
  localparam logic [11:0] A_ERR_INFO    = 12'h068;  // RO
  localparam logic [11:0] A_ERR_COUNT   = 12'h06C;  // RO
  localparam logic [11:0] A_FIN_STATUS  = 12'h070;  // RO
  localparam logic [11:0] A_FIN_VALUE   = 12'h074;  // RO
  localparam logic [11:0] A_RTC_LO      = 12'h080;  // R live (snapshots HI) / W stage
  localparam logic [11:0] A_RTC_HI      = 12'h084;  // R snapshot / W commit
  localparam logic [11:0] A_RTC_INC     = 12'h088;  // RW, ns per cycle Q8.24
  localparam logic [11:0] A_MEM_CTRL    = 12'h0A0;  // W start / R status
  localparam logic [11:0] A_MEM_BASE_LO = 12'h0A4;
  localparam logic [11:0] A_MEM_BASE_HI = 12'h0A8;
  localparam logic [11:0] A_MEM_SIZE_LO = 12'h0AC;
  localparam logic [11:0] A_MEM_SIZE_HI = 12'h0B0;
  localparam logic [11:0] A_MEM_SEED_LO = 12'h0B4;
  localparam logic [11:0] A_MEM_SEED_HI = 12'h0B8;
  localparam logic [11:0] A_MEM_MISM    = 12'h0BC;  // RO
  localparam logic [11:0] A_MEM_FADDR_LO = 12'h0C0; // RO
  localparam logic [11:0] A_MEM_FADDR_HI = 12'h0C4; // RO
  localparam logic [11:0] A_MEM_CYC_LO  = 12'h0C8;  // RO
  localparam logic [11:0] A_MEM_CYC_HI  = 12'h0CC;  // RO
  localparam logic [11:0] A_MEM_RERR    = 12'h0D0;  // RO

  localparam logic [31:0] ID_VALUE      = 32'h5349_474C;  // "SIGL"
  localparam logic [31:0] VERSION_VALUE = 32'h0004_0001;  // platform v4, rev 1
  // Default RTC increment: 10^6 / CORE_CLK_KHZ ns per cycle, Q8.24.
  localparam logic [63:0] RTC_INC_DEF64 = (64'd1000000 << 24) / 64'(CORE_CLK_KHZ);

  // Control registers.
  logic        rst_req_q, cache_en_q;
  logic [63:0] boot_pc_q;
  logic [31:0] scratch_q;
  // Trap capture (cleared while the SoC is held in reset).
  logic [31:0] trap_count_q;
  logic [63:0] trap_cause_q, trap_pc_q;
  logic [31:0] cycle_hi_q;
  logic        tx_drop_q;
  logic [31:0] host_flags_q;
  logic [31:0] rtc_lo_stage_q, rtc_hi_snap_q, rtc_inc_q;
  logic [1:0]  eng_mode_q;
  logic [63:0] eng_base_q, eng_size_q, eng_seed_q;
  // UART_TX_DATA3 read in progress: bytes gathered so far.
  logic        rd3_q;
  logic [1:0]  rd3_n_q;
  logic [23:0] rd3_d_q;

  assign soc_reset_req_o = rst_req_q;
  assign boot_pc_o = boot_pc_q;
  assign cache_en_o = cache_en_q;
  assign uart_tx_drop_o = tx_drop_q;
  assign rtc_inc_o = rtc_inc_q;
  // The engine samples its mode with the start pulse (same write).
  assign eng_mode_o = eng_start_o ? w_data_q[5:4] : eng_mode_q;
  assign eng_base_o = eng_base_q;
  assign eng_size_o = eng_size_q;
  assign eng_seed_o = eng_seed_q;

  // ---- write channel: AW and W may arrive in either order ----------
  logic        aw_have_q, w_have_q;
  logic [11:0] aw_addr_q;
  logic [31:0] w_data_q;
  logic        do_write;
  assign s_axil_awready = !aw_have_q && !s_axil_bvalid;
  assign s_axil_wready  = !w_have_q && !s_axil_bvalid;
  assign s_axil_bresp   = 2'b00;
  assign do_write = aw_have_q && w_have_q && !s_axil_bvalid;
  assign uart_rx_push_o = do_write && (aw_addr_q == A_RX_DATA) && !uart_rx_full_i;
  assign uart_rx_data_o = w_data_q[7:0];
  assign err_clr_o = do_write && (aw_addr_q == A_CTRL) && w_data_q[3];
  assign rtc_set_o = do_write && (aw_addr_q == A_RTC_HI);
  assign rtc_set_ns_o = {w_data_q, rtc_lo_stage_q};
  assign eng_start_o = do_write && (aw_addr_q == A_MEM_CTRL) && w_data_q[0];

  // ---- read channel ------------------------------------------------
  logic        rd_fire;
  logic [11:0] rd_addr;
  assign s_axil_arready = !s_axil_rvalid && !rd3_q;
  assign s_axil_rresp   = 2'b00;
  assign rd_fire = s_axil_arvalid && s_axil_arready;
  assign rd_addr = {s_axil_araddr[11:2], 2'b00};
  // UART_TX_DATA3: pop one byte per cycle (up to three) while the FIFO
  // has data, then answer.
  logic rd3_pop;
  assign rd3_pop = rd3_q && uart_tx_valid_i && (rd3_n_q != 2'd3);
  assign uart_tx_pop_o = (rd_fire && (rd_addr == A_TX_DATA) && uart_tx_valid_i) || rd3_pop;
  // Only the low 12 address bits decode (registers alias across the
  // BAR); the byte offset within a word is ignored.
  /* verilator lint_off UNUSEDSIGNAL */
  logic unused_addr_bits;
  assign unused_addr_bits = ^{s_axil_awaddr[31:12], s_axil_awaddr[1:0],
                              s_axil_araddr[31:12], s_axil_araddr[1:0]};
  /* verilator lint_on UNUSEDSIGNAL */

  logic [31:0] rd_mux;
  always_comb begin
    unique case (rd_addr)
      A_ID:            rd_mux = ID_VALUE;
      A_VERSION:       rd_mux = VERSION_VALUE;
      A_CTRL:          rd_mux = {29'd0, tx_drop_q, cache_en_q, rst_req_q};
      A_STATUS:        rd_mux = {20'd0, fin_event_i, eng_fail_i, eng_done_i,
                                 eng_busy_i, hbm_ready_i,
                                 ddr_ready_i, uart_tx_valid_i,
                                 trap_count_q != 32'd0, uart_rx_full_i,
                                 uart_tx_overflow_i, mem_err_i, soc_in_reset_i};
      A_BOOT_PC_LO:    rd_mux = boot_pc_q[31:0];
      A_BOOT_PC_HI:    rd_mux = boot_pc_q[63:32];
      A_CYCLE_LO:      rd_mux = cycle_count_i[31:0];
      A_CYCLE_HI:      rd_mux = cycle_hi_q;
      A_TRAP_COUNT:    rd_mux = trap_count_q;
      A_CLK_KHZ:       rd_mux = CORE_CLK_KHZ;
      A_TRAP_CAUSE_LO: rd_mux = trap_cause_q[31:0];
      A_TRAP_CAUSE_HI: rd_mux = trap_cause_q[63:32];
      A_TRAP_PC_LO:    rd_mux = trap_pc_q[31:0];
      A_TRAP_PC_HI:    rd_mux = trap_pc_q[63:32];
      A_SCRATCH:       rd_mux = scratch_q;
      A_HOST_FLAGS:    rd_mux = host_flags_q;
      A_RAM_SIZE_MB:   rd_mux = RAM_SIZE_MB;
      A_CAPS:          rd_mux = {31'd0, HBM_PRESENT};
      A_ERR_ADDR_LO:   rd_mux = err_addr_i[31:0];
      A_ERR_ADDR_HI:   rd_mux = err_addr_i[63:32];
      A_ERR_INFO:      rd_mux = err_info_i;
      A_ERR_COUNT:     rd_mux = err_count_i;
      A_FIN_STATUS:    rd_mux = {31'd0, fin_event_i};
      A_FIN_VALUE:     rd_mux = fin_value_i;
      A_RTC_LO:        rd_mux = rtc_ns_i[31:0];
      A_RTC_HI:        rd_mux = rtc_hi_snap_q;
      A_RTC_INC:       rd_mux = rtc_inc_q;
      A_MEM_CTRL:      rd_mux = {26'd0, eng_mode_q, 1'b0, eng_fail_i, eng_done_i, eng_busy_i};
      A_MEM_BASE_LO:   rd_mux = eng_base_q[31:0];
      A_MEM_BASE_HI:   rd_mux = eng_base_q[63:32];
      A_MEM_SIZE_LO:   rd_mux = eng_size_q[31:0];
      A_MEM_SIZE_HI:   rd_mux = eng_size_q[63:32];
      A_MEM_SEED_LO:   rd_mux = eng_seed_q[31:0];
      A_MEM_SEED_HI:   rd_mux = eng_seed_q[63:32];
      A_MEM_MISM:      rd_mux = eng_mism_i;
      A_MEM_FADDR_LO:  rd_mux = eng_fail_addr_i[31:0];
      A_MEM_FADDR_HI:  rd_mux = eng_fail_addr_i[63:32];
      A_MEM_CYC_LO:    rd_mux = eng_cycles_i[31:0];
      A_MEM_CYC_HI:    rd_mux = eng_cycles_i[63:32];
      A_MEM_RERR:      rd_mux = eng_rerr_i;
      A_TX_DATA:       rd_mux = {uart_tx_valid_i, 23'd0,
                                 uart_tx_valid_i ? uart_tx_data_i : 8'h00};
      A_TX_STATUS:     rd_mux = {uart_tx_overflow_i, 15'd0,
                                 16'(uart_tx_count_i)};
      A_RX_STATUS:     rd_mux = {uart_rx_full_i, 15'd0, 16'(uart_rx_count_i)};
      default:         rd_mux = 32'hBAAD_DEC0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      aw_have_q <= 1'b0;
      w_have_q <= 1'b0;
      aw_addr_q <= '0;
      w_data_q <= '0;
      s_axil_bvalid <= 1'b0;
      s_axil_rvalid <= 1'b0;
      s_axil_rdata <= '0;
      rst_req_q <= 1'b1;
      cache_en_q <= 1'b1;
      boot_pc_q <= 64'h1000;
      scratch_q <= '0;
      cycle_hi_q <= '0;
      tx_drop_q <= 1'b0;
      host_flags_q <= '0;
      rtc_lo_stage_q <= '0;
      rtc_hi_snap_q <= '0;
      rtc_inc_q <= RTC_INC_DEF64[31:0];
      eng_mode_q <= 2'd0;
      eng_base_q <= '0;
      eng_size_q <= '0;
      eng_seed_q <= '0;
      rd3_q <= 1'b0;
      rd3_n_q <= 2'd0;
      rd3_d_q <= '0;
      trap_count_q <= '0;
      trap_cause_q <= '0;
      trap_pc_q <= '0;
    end else begin
      // Write side.
      if (s_axil_awvalid && s_axil_awready) begin
        aw_have_q <= 1'b1;
        aw_addr_q <= {s_axil_awaddr[11:2], 2'b00};
      end
      if (s_axil_wvalid && s_axil_wready) begin
        w_have_q <= 1'b1;
        w_data_q <= s_axil_wdata;
      end
      if (do_write) begin
        aw_have_q <= 1'b0;
        w_have_q <= 1'b0;
        s_axil_bvalid <= 1'b1;
        unique case (aw_addr_q)
          A_CTRL: begin
            rst_req_q <= w_data_q[0];
            cache_en_q <= w_data_q[1];
            tx_drop_q <= w_data_q[2];
          end
          A_BOOT_PC_LO: boot_pc_q[31:0] <= w_data_q;
          A_BOOT_PC_HI: boot_pc_q[63:32] <= w_data_q;
          A_SCRATCH:    scratch_q <= w_data_q;
          A_HOST_FLAGS: host_flags_q <= w_data_q;
          A_RTC_LO:     rtc_lo_stage_q <= w_data_q;
          A_RTC_INC:    rtc_inc_q <= w_data_q;
          A_MEM_CTRL:   if (w_data_q[0] && !eng_busy_i) eng_mode_q <= w_data_q[5:4];
          A_MEM_BASE_LO: eng_base_q[31:0] <= w_data_q;
          A_MEM_BASE_HI: eng_base_q[63:32] <= w_data_q;
          A_MEM_SIZE_LO: eng_size_q[31:0] <= w_data_q;
          A_MEM_SIZE_HI: eng_size_q[63:32] <= w_data_q;
          A_MEM_SEED_LO: eng_seed_q[31:0] <= w_data_q;
          A_MEM_SEED_HI: eng_seed_q[63:32] <= w_data_q;
          default: ;
        endcase
      end else if (s_axil_bvalid && s_axil_bready) begin
        s_axil_bvalid <= 1'b0;
      end
      // Read side.
      if (rd_fire && rd_addr == A_TX_DATA3) begin
        rd3_q <= 1'b1;
        rd3_n_q <= 2'd0;
        rd3_d_q <= '0;
      end else if (rd_fire) begin
        s_axil_rvalid <= 1'b1;
        s_axil_rdata <= rd_mux;
        if (rd_addr == A_CYCLE_LO) cycle_hi_q <= cycle_count_i[63:32];
        if (rd_addr == A_RTC_LO) rtc_hi_snap_q <= rtc_ns_i[63:32];
      end else if (s_axil_rvalid && s_axil_rready) begin
        s_axil_rvalid <= 1'b0;
      end
      if (rd3_pop) begin
        rd3_d_q[8*rd3_n_q +: 8] <= uart_tx_data_i;
        rd3_n_q <= rd3_n_q + 2'd1;
      end else if (rd3_q) begin
        // FIFO empty or three bytes: answer {any, n, bytes}.
        rd3_q <= 1'b0;
        s_axil_rvalid <= 1'b1;
        s_axil_rdata <= {rd3_n_q != 2'd0, 5'd0, rd3_n_q, rd3_d_q};
      end
      // Trap capture.
      if (soc_in_reset_i) begin
        trap_count_q <= '0;
      end else if (trap_i) begin
        trap_count_q <= trap_count_q + 32'd1;
        trap_cause_q <= trap_cause_i;
        trap_pc_q <= trap_pc_i;
      end
    end
  end
endmodule
`default_nettype wire
