// Goldfish RTC ("google,goldfish-rtc", QEMU virt layout; issue #67,
// docs/LINUX_PLATFORM.md) at SoC 0x0010_1000. Time is nanoseconds
// since the Unix epoch.
//
// Time base: rtc_ns_i is a free-running nanosecond count kept by the
// platform outside the SoC reset domain (the FPGA top keeps it from
// the CL reset on, and the host sets it to wall-clock time before
// releasing the SoC; simulation and ASIC builds may tie it to 0). The
// RTC reads now = rtc_ns_i + offset_q; guest writes to TIME_LOW /
// TIME_HIGH move offset_q (QEMU semantics: the written half replaces
// that half of the current time), so they last until the next SoC
// reset, which returns to the platform time.
//
// Registers (32-bit, byte offsets):
//   0x00 TIME_LOW         R: now[31:0], latches now[63:32] for TIME_HIGH
//                         W: set now[31:0]
//   0x04 TIME_HIGH        R: the latched high half;  W: set now[63:32]
//   0x08 ALARM_LOW        R/W alarm[31:0]; a write arms the alarm
//   0x0C ALARM_HIGH       R/W alarm[63:32]
//   0x10 IRQ_ENABLED      R/W bit 0
//   0x14 CLEAR_ALARM      W: disarm
//   0x18 ALARM_STATUS     R: 1 while armed
//   0x1C CLEAR_INTERRUPT  W: clear the pending interrupt
// An armed alarm fires when now >= alarm: it disarms and sets the
// pending interrupt; irq_o = pending && enabled (level, PLIC source
// 11 as in QEMU virt). Bus: the core's aligned 64-bit device word; a
// 64-bit load at offset 0 returns the live 64-bit time.
`default_nettype none
module sigil_rtc_goldfish (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        sel_i,      // access to this 4 KiB page
    input  wire        re_i,       // data load (side effects)
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [11:0] addr_i,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [7:0]  be_i,
    input  wire [63:0] wdata_i,
    output logic [63:0] rdata_o,
    input  wire [63:0] rtc_ns_i,
    output wire        irq_o
);
  logic [63:0] offset_q, alarm_q, now;
  logic [31:0] time_high_q;
  logic        irq_en_q, alarm_run_q, irq_pend_q;
  assign now = rtc_ns_i + offset_q;
  assign irq_o = irq_pend_q && irq_en_q;

  logic [2:0] word;   // 64-bit word index within the 32-byte block
  assign word = addr_i[5:3];
  logic in_blk;
  assign in_blk = (addr_i[11:5] == 7'd0);

  // Write data of the two 32-bit registers in this 64-bit word.
  logic [31:0] wlo, whi;
  logic        wr_lo, wr_hi;
  assign wlo = wdata_i[31:0];
  assign whi = wdata_i[63:32];
  assign wr_lo = sel_i && in_blk && (be_i[3:0] != 4'd0);
  assign wr_hi = sel_i && in_blk && (be_i[7:4] != 4'd0);

  always_comb begin
    rdata_o = 64'd0;
    if (in_blk) begin
      unique case (word)
        3'd0: rdata_o = addr_i[2] ? {time_high_q, 32'd0} : now;
        3'd1: rdata_o = alarm_q;
        3'd2: rdata_o = {32'd0, 31'd0, irq_en_q};
        3'd3: rdata_o = {31'd0, alarm_run_q, 32'd0};
        default: rdata_o = 64'd0;
      endcase
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      offset_q <= 64'd0;
      alarm_q <= 64'd0;
      time_high_q <= 32'd0;
      irq_en_q <= 1'b0;
      alarm_run_q <= 1'b0;
      irq_pend_q <= 1'b0;
    end else begin
      if (alarm_run_q && (now >= alarm_q)) begin
        alarm_run_q <= 1'b0;
        irq_pend_q <= 1'b1;
      end
      if (sel_i && re_i && in_blk && word == 3'd0 && !addr_i[2]) begin
        time_high_q <= now[63:32];
      end
      unique case (word)
        3'd0: begin
          // TIME_LOW / TIME_HIGH: offset = new time - platform time.
          if (wr_lo && wr_hi) offset_q <= {whi, wlo} - rtc_ns_i;
          else if (wr_lo) offset_q <= {now[63:32], wlo} - rtc_ns_i;
          else if (wr_hi) offset_q <= {whi, now[31:0]} - rtc_ns_i;
        end
        3'd1: begin
          if (wr_lo) begin
            alarm_q[31:0] <= wlo;
            alarm_run_q <= 1'b1;
          end
          if (wr_hi) alarm_q[63:32] <= whi;
        end
        3'd2: begin
          if (wr_lo) irq_en_q <= wlo[0];
          if (wr_hi) alarm_run_q <= 1'b0;     // CLEAR_ALARM
        end
        3'd3: begin
          if (wr_hi) irq_pend_q <= 1'b0;      // CLEAR_INTERRUPT
        end
        default: ;
      endcase
    end
  end
endmodule
`default_nettype wire
