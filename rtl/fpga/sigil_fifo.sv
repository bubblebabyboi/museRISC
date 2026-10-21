// Small synchronous FIFO (first-word fall-through) for the FPGA
// top's virtual-UART byte queues (issue #52). One clock domain;
// data_o shows the head entry whenever empty_o is low. A push
// while full or a pop while empty is ignored (the caller checks
// full_o / empty_o); flush_i empties it (takes priority). Storage
// has no reset (LUTRAM/BRAM-friendly); only the pointers do.
// DEPTH must be a power of two >= 2.
`default_nettype none
module sigil_fifo #(
    parameter int unsigned WIDTH = 8,
    parameter int unsigned DEPTH = 16
) (
    input  wire              clk_i,
    input  wire              rst_ni,
    input  wire              flush_i,
    input  wire              push_i,
    input  wire [WIDTH-1:0]  data_i,
    output logic             full_o,
    input  wire              pop_i,
    output logic [WIDTH-1:0] data_o,
    output logic             empty_o,
    output logic [$clog2(DEPTH):0] count_o
);
  localparam int unsigned AW = $clog2(DEPTH);
  logic [WIDTH-1:0] mem_q [DEPTH];
  logic [AW-1:0] wptr_q, rptr_q;
  logic [AW:0]   count_q;
  logic do_push, do_pop;

  assign full_o = (count_q == (AW + 1)'(DEPTH));
  assign empty_o = (count_q == '0);
  assign count_o = count_q;
  assign data_o = mem_q[rptr_q];
  assign do_push = push_i && !full_o;
  assign do_pop = pop_i && !empty_o;

  always_ff @(posedge clk_i) begin
    if (do_push) mem_q[wptr_q] <= data_i;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wptr_q <= '0;
      rptr_q <= '0;
      count_q <= '0;
    end else if (flush_i) begin
      wptr_q <= '0;
      rptr_q <= '0;
      count_q <= '0;
    end else begin
      if (do_push) wptr_q <= wptr_q + 1'b1;
      if (do_pop) rptr_q <= rptr_q + 1'b1;
      unique case ({do_push, do_pop})
        2'b10: count_q <= count_q + 1'b1;
        2'b01: count_q <= count_q - 1'b1;
        default: count_q <= count_q;
      endcase
    end
  end
endmodule
`default_nettype wire
