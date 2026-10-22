// 16550A-compatible UART subset (byte registers, layout and
// interrupt ids mirror tb/cpp/soc_tb.cpp). Serial TX/RX use
// the standard 16x divisor latch (bit period = 16*divisor
// clocks of clk_i); a parallel byte stream is exposed for
// simulation/host capture. Bus is the core's aligned-64-bit word:
// rdata_o packs registers 7..0 into byte lanes.
//
// Transmit (issue #63): a 16-byte TX FIFO in front of the serial
// shifter, as on a real 16550A. THR writes are accepted while the
// FIFO has room (a write to a full FIFO is dropped, as on the real
// part); LSR.THRE (bit 5) = TX FIFO empty, LSR.TEMT (bit 6) = FIFO
// empty and shifter idle; the THRE interrupt fires when the FIFO
// runs empty (or ETBEI is enabled with it empty) and clears on an
// IIR read or a THR write. Linux's 8250 driver ("ns16550a": 16-byte
// FIFO) writes up to 16 bytes per THRE without re-reading LSR; the
// previous single-byte THR silently dropped bytes 3..16 of such a
// burst (#63). FCR bit 2 clears the TX FIFO, bit 1 the RX FIFO.
// tx_valid_o / tx_data_o pulse when a byte leaves the FIFO into the
// shifter (start of its serial frame). tx_stall_i = 1 holds the
// next byte in the FIFO (byte sink full: the FPGA virtual UART uses
// it so a slow host never loses bytes); tie it to 0 otherwise.
//
// Receive: rx bytes may be pushed on rx_data_i/rx_valid_i;
// rx_ready_o is high when a byte pushed this cycle is accepted, i.e.
// the RX FIFO has room and no serial byte lands in the same cycle.
`default_nettype none
module sigil_uart16550 (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire [2:0]  addr_i,
    input  wire        re_i,
    input  wire [7:0]  be_i,
    input  wire [63:0] wdata_i,
    output wire [63:0] rdata_o,
    output wire        irq_o,
    output wire        tx_o,
    input  wire        rx_i,
    output wire [7:0]  tx_data_o,
    output wire        tx_valid_o,
    input  wire        tx_stall_i,
    input  wire [7:0]  rx_data_i,
    input  wire        rx_valid_i,
    output wire        rx_ready_o
);
  logic [7:0] ier_q, lcr_q, mcr_q, scr_q, dll_q, dlm_q;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [7:0] fcr_q;  // 16550 FCR is write-only
  /* verilator lint_on UNUSEDSIGNAL */
  logic       thre_irq_q;
  // RX FIFO (16 entries).
  logic [7:0] rx_fifo_q [0:15];
  logic [3:0] rx_head_q, rx_tail_q;
  logic [4:0] rx_count_q;
  logic       rx_push_ser, rx_push_par;
  logic [7:0] rx_byte_ser;
  // TX FIFO (16 entries) + shift register.
  logic [7:0] tx_fifo_q [0:15];
  logic [3:0] tx_head_q, tx_tail_q;
  logic [4:0] tx_count_q;
  logic [9:0] shift_q;
  logic       tx_busy_q;
  logic [15:0] bit_cnt_q;
  logic [3:0]  bit_idx_q;

  logic [15:0] divisor;
  assign divisor = ({dlm_q, dll_q} == 16'd0) ? 16'd1 : {dlm_q, dll_q};
  logic [20:0] cycles_per_bit;
  assign cycles_per_bit = {5'd0, divisor} << 4;

  logic dlab;
  assign dlab = lcr_q[7];
  logic rx_avail, tx_empty, tx_full;
  assign rx_avail = (rx_count_q != 5'd0);
  assign tx_empty = (tx_count_q == 5'd0);
  assign tx_full = tx_count_q[4];
  assign irq_o = (rx_avail && ier_q[0]) || (thre_irq_q && ier_q[1]);
  assign tx_o = tx_busy_q ? shift_q[0] : 1'b1;

  logic [7:0] iir_val;
  assign iir_val = (rx_avail && ier_q[0]) ? 8'hC4 :
                   (thre_irq_q && ier_q[1]) ? 8'hC2 : 8'hC1;
  logic [7:0] lsr_val;
  assign lsr_val = {1'b0, ~tx_busy_q && tx_empty, tx_empty, 4'd0, rx_avail};
  assign rdata_o = {scr_q, 8'd0, lsr_val, mcr_q, lcr_q, iir_val,
                    dlab ? dlm_q : ier_q,
                    dlab ? dll_q :
                        (rx_avail ? rx_fifo_q[rx_head_q] : 8'd0)};

  logic [7:0] wr_byte;
  assign wr_byte = wdata_i[8*addr_i +: 8];
  logic wr_strobe;
  assign wr_strobe = be_i[addr_i];
  logic thr_wr, tx_push, tx_pop, tx_clr;
  assign thr_wr = wr_strobe && (addr_i == 3'd0) && !dlab;
  assign tx_push = thr_wr && !tx_full;
  assign tx_clr = wr_strobe && (addr_i == 3'd2) && wr_byte[2];
  // The shifter takes the next byte when idle and the sink is ready.
  assign tx_pop = !tx_busy_q && !tx_empty && !tx_stall_i;
  assign tx_valid_o = tx_pop;
  assign tx_data_o = tx_fifo_q[tx_head_q];

  // Serial RX: synchronize, detect start, sample mid-bit.
  logic rx_sync_q, rx_prev_q, rx_active_q;
  logic [20:0] rx_cnt_q;
  logic [3:0]  rx_idx_q;
  logic [7:0]  rx_shift_q;
  assign rx_ready_o = (rx_count_q < 5'd16) && !rx_push_ser;
  assign rx_push_par = rx_valid_i && rx_ready_o;

  always_ff @(posedge clk_i) begin
    if (tx_push) tx_fifo_q[tx_tail_q] <= wr_byte;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ier_q <= 8'd0; lcr_q <= 8'd0; mcr_q <= 8'd0; fcr_q <= 8'd0;
      scr_q <= 8'd0; dll_q <= 8'd1; dlm_q <= 8'd0;
      thre_irq_q <= 1'b0;
      rx_head_q <= 4'd0; rx_tail_q <= 4'd0; rx_count_q <= 5'd0;
      tx_head_q <= 4'd0; tx_tail_q <= 4'd0; tx_count_q <= 5'd0;
      shift_q <= 10'h3FF; tx_busy_q <= 1'b0;
      bit_cnt_q <= 16'd0; bit_idx_q <= 4'd0;
      rx_sync_q <= 1'b1; rx_prev_q <= 1'b1; rx_active_q <= 1'b0;
      rx_cnt_q <= 21'd0; rx_idx_q <= 4'd0; rx_shift_q <= 8'd0;
      rx_push_ser <= 1'b0; rx_byte_ser <= 8'd0;
    end else begin
      rx_push_ser <= 1'b0;
      // TX serializer.
      if (tx_busy_q) begin
        if (bit_cnt_q == 16'd0) begin
          shift_q <= {1'b1, shift_q[9:1]};
          bit_cnt_q <= cycles_per_bit[15:0] - 16'd1;
          if (bit_idx_q == 4'd9) begin
            tx_busy_q <= 1'b0;
          end else begin
            bit_idx_q <= bit_idx_q + 4'd1;
          end
        end else begin
          bit_cnt_q <= bit_cnt_q - 16'd1;
        end
      end else if (tx_pop) begin
        shift_q <= {1'b1, tx_fifo_q[tx_head_q], 1'b0};
        tx_busy_q <= 1'b1;
        bit_idx_q <= 4'd0;
        bit_cnt_q <= cycles_per_bit[15:0] - 16'd1;
      end
      // TX FIFO accounting (a clear wins over a same-cycle push/pop).
      if (tx_clr) begin
        tx_head_q <= 4'd0;
        tx_tail_q <= 4'd0;
        tx_count_q <= 5'd0;
      end else begin
        if (tx_push) tx_tail_q <= tx_tail_q + 4'd1;
        if (tx_pop) tx_head_q <= tx_head_q + 4'd1;
        case ({tx_push, tx_pop})
          2'b10: tx_count_q <= tx_count_q + 5'd1;
          2'b01: tx_count_q <= tx_count_q - 5'd1;
          default: tx_count_q <= tx_count_q;
        endcase
      end
      // THRE interrupt: set when the FIFO runs empty (last byte into
      // the shifter, or a TX FIFO clear); cleared by a THR write or
      // an IIR read.
      if ((tx_pop && tx_count_q == 5'd1 && !tx_push) || tx_clr) begin
        thre_irq_q <= 1'b1;
      end else if (thr_wr) begin
        thre_irq_q <= 1'b0;
      end
      // RX serializer.
      rx_sync_q <= rx_i;
      rx_prev_q <= rx_sync_q;
      if (!rx_active_q) begin
        if (rx_prev_q && !rx_sync_q) begin
          rx_active_q <= 1'b1;
          rx_cnt_q <= (cycles_per_bit >> 1) - 21'd1;
          rx_idx_q <= 4'd0;
        end
      end else if (rx_cnt_q == 21'd0) begin
        rx_cnt_q <= cycles_per_bit - 21'd1;
        if (rx_idx_q < 4'd8) begin
          rx_shift_q[rx_idx_q[2:0]] <= rx_sync_q;
          rx_idx_q <= rx_idx_q + 4'd1;
        end else begin
          rx_active_q <= 1'b0;
          if (rx_sync_q && rx_count_q < 5'd16) begin
            rx_byte_ser <= rx_shift_q;
            rx_push_ser <= 1'b1;
          end
        end
      end else begin
        rx_cnt_q <= rx_cnt_q - 21'd1;
      end
      // RX FIFO push/pop accounting.
      if (rx_push_ser || rx_push_par) begin
        rx_fifo_q[rx_tail_q] <= rx_push_ser ? rx_byte_ser : rx_data_i;
        rx_tail_q <= rx_tail_q + 4'd1;
      end
      case ({(rx_push_ser || rx_push_par),
             (re_i && addr_i == 3'd0 && !dlab && rx_avail)})
        2'b10: rx_count_q <= rx_count_q + 5'd1;
        2'b01: rx_count_q <= rx_count_q - 5'd1;
        default: rx_count_q <= rx_count_q;
      endcase
      if (re_i && addr_i == 3'd0 && !dlab && rx_avail) begin
        rx_head_q <= rx_head_q + 4'd1;
      end
      if (re_i && addr_i == 3'd2) thre_irq_q <= 1'b0;
      // Register writes.
      if (wr_strobe) begin
        unique case (addr_i)
          3'd0: begin
            if (dlab) dll_q <= wr_byte;
          end
          3'd1: begin
            if (dlab) dlm_q <= wr_byte;
            else begin
              ier_q <= wr_byte & 8'h0F;
              if (wr_byte[1] && tx_empty) thre_irq_q <= 1'b1;
            end
          end
          3'd2: begin
            fcr_q <= wr_byte;
            if (wr_byte[1]) begin
              rx_head_q <= 4'd0;
              rx_tail_q <= 4'd0;
              rx_count_q <= 5'd0;
            end
          end
          3'd3: lcr_q <= wr_byte;
          3'd4: mcr_q <= wr_byte;
          3'd7: scr_q <= wr_byte;
          default: begin end
        endcase
      end
    end
  end
endmodule
`default_nettype wire
