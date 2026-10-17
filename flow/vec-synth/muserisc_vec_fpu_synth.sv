// Synthesis-only wrapper (scripts/synth_block_orfs.sh): muserisc_vec
// plus the shared muserisc_fpu behind the core's port mux (vec busy
// selects the vector unit), so vec -> FPU -> vec paths are timed.
`default_nettype none
module muserisc_vec_fpu_synth (
    input  wire          clk_i,
    input  wire          rst_ni,
    input  wire          kill_i,
    input  wire          start_i,
    input  wire          ack_i,
    input  wire [6:0]    op_i,
    input  wire [1:0]    form_i,
    input  wire [2:0]    sew_i,
    input  wire [63:0]   vl_i,
    input  wire [63:0]   vstart_i,
    input  wire [63:0]   vlmax_i,
    input  wire          vta_i,
    input  wire          vma_i,
    input  wire          vm_i,
    input  wire [4:0]    vs2_i,
    input  wire [4:0]    vs1_i,
    input  wire [4:0]    vd_i,
    input  wire [3:0]    nreg_i,
    input  wire [63:0]   scalar_i,
    input  wire [63:0]   imm_i,
    input  wire [1:0]    vxrm_i,
    input  wire [2:0]    frm_i,
    output logic         re_a_o,
    output logic [7:0]   raddr_a_o,
    input  wire  [63:0]  rdata_a_i,
    output logic         re_b_o,
    output logic [7:0]   raddr_b_o,
    input  wire  [63:0]  rdata_b_i,
    output logic         re_c_o,
    output logic [7:0]   raddr_c_o,
    input  wire  [63:0]  rdata_c_i,
    input  wire  [511:0] v0_i,
    output logic         we_o,
    output logic [7:0]   waddr_o,
    output logic [7:0]   wbe_o,
    output logic [63:0]  wdata_o,
    output logic         busy_o,
    output logic         done_o,
    output logic [63:0]  scalar_o,
    output logic         sat_o,
    output logic [4:0]   fflags_o,
    // scalar FP side (the core's EX operands)
    input  wire          s_req_i,
    input  wire          s_ack_i,
    input  wire [4:0]    s_op_i,
    input  wire          s_d_i,
    input  wire [2:0]    s_rm_i,
    input  wire [63:0]   s_a_i,
    input  wire [63:0]   s_b_i,
    input  wire [63:0]   s_c_i,
    input  wire [1:0]    s_aux_i,
    output logic         s_done_o,
    output logic [63:0]  s_result_o,
    output logic [4:0]   s_flags_o
);
  logic        f_req, f_d;
  logic [4:0]  f_op;
  logic [2:0]  f_rm;
  logic [1:0]  f_aux;
  logic [63:0] f_a, f_b, f_c;
  muserisc_vec u_vec (
      .clk_i, .rst_ni, .kill_i, .start_i, .ack_i, .op_i, .form_i, .sew_i,
      .vl_i, .vstart_i, .vlmax_i, .vta_i, .vma_i, .vm_i, .vs2_i, .vs1_i,
      .vd_i, .nreg_i, .scalar_i, .imm_i, .vxrm_i, .frm_i,
      .re_a_o, .raddr_a_o, .rdata_a_i, .re_b_o, .raddr_b_o, .rdata_b_i,
      .re_c_o, .raddr_c_o, .rdata_c_i, .v0_i, .we_o, .waddr_o, .wbe_o,
      .wdata_o, .busy_o, .done_o, .scalar_o, .sat_o, .fflags_o,
      .fpu_req_o(f_req), .fpu_op_o(f_op), .fpu_fmt_d_o(f_d), .fpu_rm_o(f_rm),
      .fpu_a_o(f_a), .fpu_b_o(f_b), .fpu_c_o(f_c), .fpu_aux_o(f_aux),
      .fpu_done_i(s_done_o), .fpu_result_i(s_result_o), .fpu_flags_i(s_flags_o));
  muserisc_fpu u_fpu (
      .clk_i, .rst_ni,
      .req_i   (busy_o ? f_req : s_req_i),
      .ack_i   (busy_o || s_ack_i),
      .kill_i,
      .done_o  (s_done_o),
      .op_i    (busy_o ? f_op : s_op_i),
      .fmt_d_i (busy_o ? f_d : s_d_i),
      .rm_i    (busy_o ? f_rm : s_rm_i),
      .a_i     (busy_o ? f_a : s_a_i),
      .b_i     (busy_o ? f_b : s_b_i),
      .c_i     (busy_o ? f_c : s_c_i),
      .aux_i   (busy_o ? f_aux : s_aux_i),
      .result_o(s_result_o),
      .flags_o (s_flags_o));
endmodule
`default_nettype wire
