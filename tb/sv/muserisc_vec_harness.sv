// Unit-test harness for the element-serial vector unit:
// muserisc_vec wired to the banked VRF exactly as in the
// core, plus a testbench backdoor that loads (write port)
// and dumps (read port C) VRF words while the unit is idle.
`default_nettype none
module muserisc_vec_harness (
    input  wire          clk_i,
    input  wire          rst_ni,
    // Backdoor (ignored while the unit is busy).
    input  wire          tb_we_i,
    input  wire [7:0]    tb_waddr_i,
    input  wire [63:0]   tb_wdata_i,
    input  wire          tb_re_i,
    input  wire [7:0]    tb_raddr_i,
    output logic [63:0]  tb_rdata_o,
    // Vector unit control (see muserisc_vec).
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
    output logic         busy_o,
    output logic         done_o,
    output logic [63:0]  scalar_o,
    output logic         sat_o,
    output logic [4:0]   fflags_o,
    output logic         we_o       // unit VRF write strobe (observability)
);
  logic        re_a, re_b, re_c, we;
  logic [7:0]  ra_a, ra_b, ra_c, wa, wbe;
  logic [63:0] rd_a, rd_b, rd_c, wd;
  logic [511:0] v0;
  logic        u_re_c, u_we;
  logic [7:0]  u_ra_c, u_wa, u_wbe;
  logic [63:0] u_wd;
  logic        tb_own;
  assign tb_own = !busy_o;
  assign re_c = tb_own ? tb_re_i : u_re_c;
  assign ra_c = tb_own ? tb_raddr_i : u_ra_c;
  assign we = tb_own ? tb_we_i : u_we;
  assign wa = tb_own ? tb_waddr_i : u_wa;
  assign wbe = tb_own ? 8'hff : u_wbe;
  assign wd = tb_own ? tb_wdata_i : u_wd;
  assign tb_rdata_o = rd_c;
  assign we_o = u_we;

  muserisc_vregfile u_vrf (
      .clk_i     (clk_i),
      .re_a_i    (re_a),
      .raddr_a_i (ra_a),
      .rdata_a_o (rd_a),
      .re_b_i    (re_b),
      .raddr_b_i (ra_b),
      .rdata_b_o (rd_b),
      .re_c_i    (re_c),
      .raddr_c_i (ra_c),
      .rdata_c_o (rd_c),
      .v0_o      (v0),
      .we_i      (we),
      .waddr_i   (wa),
      .wbe_i     (wbe),
      .wdata_i   (wd)
  );

  muserisc_vec u_vec (
      .clk_i     (clk_i),
      .rst_ni    (rst_ni),
      .kill_i    (kill_i),
      .start_i   (start_i),
      .ack_i     (ack_i),
      .op_i      (op_i),
      .form_i    (form_i),
      .sew_i     (sew_i),
      .vl_i      (vl_i),
      .vstart_i  (vstart_i),
      .vlmax_i   (vlmax_i),
      .vta_i     (vta_i),
      .vma_i     (vma_i),
      .vm_i      (vm_i),
      .vs2_i     (vs2_i),
      .vs1_i     (vs1_i),
      .vd_i      (vd_i),
      .nreg_i    (nreg_i),
      .scalar_i  (scalar_i),
      .imm_i     (imm_i),
      .vxrm_i    (vxrm_i),
      .frm_i     (frm_i),
      .re_a_o    (re_a),
      .raddr_a_o (ra_a),
      .rdata_a_i (rd_a),
      .re_b_o    (re_b),
      .raddr_b_o (ra_b),
      .rdata_b_i (rd_b),
      .re_c_o    (u_re_c),
      .raddr_c_o (u_ra_c),
      .rdata_c_i (rd_c),
      .v0_i      (v0),
      .we_o      (u_we),
      .waddr_o   (u_wa),
      .wbe_o     (u_wbe),
      .wdata_o   (u_wd),
      .busy_o    (busy_o),
      .done_o    (done_o),
      .scalar_o  (scalar_o),
      .sat_o     (sat_o),
      .fflags_o  (fflags_o)
  );
endmodule
`default_nettype wire
