// Synthesis-only stub of muserisc_fpu_pkg for the vector-unit
// area/depth comparison (scripts/synth_vec.sh): fp_eval and
// fp_estimate are black-boxed as a trivial XOR of their operands
// so the scalar FP datapath (being reworked separately into a
// multi-cycle FPU) neither dominates nor blocks the comparison.
// The same stub is used for the before and after designs; the
// count of fp_eval call sites is reported separately. Since the
// vector unit runs its FP sub-steps on the shared scalar FPU,
// synthesis sees only the (stubbed) estimate stages.
package muserisc_fpu_pkg;
  localparam logic [4:0] FPU_ADD   = 5'd0;
  localparam logic [4:0] FPU_SUB   = 5'd1;
  localparam logic [4:0] FPU_MUL   = 5'd2;
  localparam logic [4:0] FPU_DIV   = 5'd3;
  localparam logic [4:0] FPU_SQRT  = 5'd4;
  localparam logic [4:0] FPU_SGNJ  = 5'd5;
  localparam logic [4:0] FPU_MINMAX= 5'd6;
  localparam logic [4:0] FPU_CMP   = 5'd7;
  localparam logic [4:0] FPU_CLASS = 5'd8;
  localparam logic [4:0] FPU_F2I   = 5'd9;
  localparam logic [4:0] FPU_I2F   = 5'd10;
  localparam logic [4:0] FPU_F2F   = 5'd11;
  localparam logic [4:0] FPU_FMA   = 5'd12;
  localparam logic [4:0] FPU_FMS   = 5'd13;
  localparam logic [4:0] FPU_FNMS  = 5'd14;
  localparam logic [4:0] FPU_FNMA  = 5'd15;
  typedef struct packed {
    logic [63:0] result;
    logic [4:0]  flags;
  } fp_eval_result_t;
  typedef struct packed {
    logic               sign;
    logic signed [15:0] exp;
    logic [52:0]        sig;
    logic               is_zero, is_inf, is_nan, is_snan, is_sub;
    logic [63:0]        raw;
  } unpacked_t;
  function automatic unpacked_t unpack(input logic [63:0] v, input logic d);
    unpack = '0;
    unpack.raw = v ^ {63'd0, d};
  endfunction
  function automatic fp_eval_result_t fp_est_fin(
      input logic rsqrt, input logic d, input logic [2:0] rm,
      input unpacked_t u);
    fp_est_fin.result = u.raw ^ {59'd0, rm, rsqrt, d};
    fp_est_fin.flags = u.raw[4:0];
  endfunction
  function automatic fp_eval_result_t fp_estimate(
      input logic rsqrt, input logic d, input logic [2:0] rm,
      input logic [63:0] v);
    fp_estimate.result = v ^ {59'd0, rm, rsqrt, d};
    fp_estimate.flags = v[4:0];
  endfunction
  function automatic fp_eval_result_t fp_eval(
      input logic [4:0] op, input logic fmt_d, input logic [2:0] rm,
      input logic [63:0] a, input logic [63:0] b, input logic [63:0] c,
      input logic [1:0] aux);
    fp_eval.result = a ^ b ^ c ^ {53'd0, op, fmt_d, rm, aux};
    fp_eval.flags = a[4:0] ^ b[4:0] ^ {aux, rm};
  endfunction
endpackage
