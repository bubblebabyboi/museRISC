// PMP check forms for one port, copied from sigil_csr.sv:
//   pmp_ser_old  - main 9da0006 serial pmp_check (first word only)
//   pmp_ser_new  - 8-riscv-dv 3ae351d serial pmp_check (wide)
//   pmp_par_old  - 53-100mhz-afi 866efb6 pmp_check_par (FPGA_TIMING)
//   pmp_par_new  - proposed port of 3ae351d to pmp_check_par
// cfg/paddr are the 16 entries flattened; WIDE selects how the wide
// input is tied (0: fetch port A, 1: walker port C, 2: input, data port B).
module pmp_forms #(parameter int FORM = 0, parameter int WIDE = 2) (
    input  logic [63:0]     addr,
    input  logic [1:0]      acc,
    input  logic [1:0]      priv,
    input  logic            wide_i,
    input  logic [16*8-1:0] cfg_flat,
    input  logic [16*54-1:0] paddr_flat,
    output logic            allow
);
  localparam logic [1:0] PRIV_M = 2'b11;
  logic [7:0]  pmpcfg_q  [0:15];
  logic [63:0] pmpaddr_q [0:15];
  always_comb for (int i = 0; i < 16; i++) begin
    pmpcfg_q[i]  = cfg_flat[i*8 +: 8];
    pmpaddr_q[i] = {10'd0, paddr_flat[i*54 +: 54]};
  end
  logic wide;
  assign wide = (WIDE == 2) ? wide_i : (WIDE == 1);

  function automatic logic pmp_match_old(
      input logic [63:0] addr, input logic [7:0] cfg,
      input logic [63:0] pmpaddr, input logic [63:0] prev_pmpaddr);
    logic [53:0] a54, enc, prev, napot_mask;
    a54 = addr[55:2];
    enc = pmpaddr[53:0];
    prev = prev_pmpaddr[53:0];
    napot_mask = enc ^ (enc + 54'd1);
    unique case (cfg[4:3])
      2'b00:   pmp_match_old = 1'b0;
      2'b01:   pmp_match_old = (a54 >= prev) && (a54 < enc);
      2'b10:   pmp_match_old = (a54 == enc);
      default: pmp_match_old = ((a54 ^ enc) & ~napot_mask) == 54'd0;
    endcase
  endfunction
  function automatic logic ser_old(input logic [63:0] addr, input logic [1:0] acc, input logic [1:0] priv);
    logic allow;
    allow = (priv == PRIV_M);
    for (int i = 15; i >= 0; i--) begin
      if (pmp_match_old(addr, pmpcfg_q[i], pmpaddr_q[i], (i == 0) ? 64'd0 : pmpaddr_q[i-1])) begin
        if ((priv == PRIV_M) && !pmpcfg_q[i][7]) allow = 1'b1;
        else if (acc == 2'd0) allow = pmpcfg_q[i][0];
        else if (acc == 2'd1) allow = pmpcfg_q[i][1];
        else if (acc == 2'd3) allow = pmpcfg_q[i][0] && pmpcfg_q[i][2];
        else allow = pmpcfg_q[i][2];
      end
    end
    return allow;
  endfunction

  function automatic logic [1:0] pmp_match_new(
      input logic [63:0] addr, input logic [7:0] cfg,
      input logic [63:0] pmpaddr, input logic [63:0] prev_pmpaddr);
    logic [53:0] a54, a54o, enc, prev, napot_mask;
    logic lo, hi, m;
    a54 = addr[55:2];
    a54o = {addr[55:3], 1'b1};
    enc = pmpaddr[53:0];
    prev = prev_pmpaddr[53:0];
    napot_mask = enc ^ (enc + 54'd1);
    unique case (cfg[4:3])
      2'b00:   pmp_match_new = 2'b00;
      2'b01: begin
        lo = (a54 >= prev);
        hi = (a54 < enc);
        pmp_match_new = {(lo || (prev == a54o)) && hi && (enc != a54o), lo && hi};
      end
      2'b10:   pmp_match_new = {a54o == enc, a54 == enc};
      default: begin
        m = ((a54 ^ enc) & ~napot_mask) == 54'd0;
        pmp_match_new = {m, m};
      end
    endcase
  endfunction
  function automatic logic ser_new(input logic [63:0] addr, input logic [1:0] acc, input logic [1:0] priv, input logic wide);
    logic allow;
    logic [1:0] m;
    allow = (priv == PRIV_M);
    for (int i = 15; i >= 0; i--) begin
      m = pmp_match_new(addr, pmpcfg_q[i], pmpaddr_q[i], (i == 0) ? 64'd0 : pmpaddr_q[i-1]);
      if (m[0] || (wide && m[1])) begin
        if (wide && (m[0] != m[1])) allow = 1'b0;
        else if ((priv == PRIV_M) && !pmpcfg_q[i][7]) allow = 1'b1;
        else if (acc == 2'd0) allow = pmpcfg_q[i][0];
        else if (acc == 2'd1) allow = pmpcfg_q[i][1];
        else if (acc == 2'd3) allow = pmpcfg_q[i][0] && pmpcfg_q[i][2];
        else allow = pmpcfg_q[i][2];
      end
    end
    return allow;
  endfunction

  function automatic logic par_old(input logic [63:0] addr, input logic [1:0] acc, input logic [1:0] priv);
    logic [53:0] a54, enc, napot_mask;
    logic [15:0] lt, ge_prev, hit, perm, first;
    a54 = addr[55:2];
    for (int i = 0; i < 16; i++) lt[i] = (a54 < pmpaddr_q[i][53:0]);
    ge_prev[0] = 1'b1;
    for (int i = 1; i < 16; i++) ge_prev[i] = !lt[i-1];
    for (int i = 0; i < 16; i++) begin
      enc = pmpaddr_q[i][53:0];
      napot_mask = enc ^ (enc + 54'd1);
      unique case (pmpcfg_q[i][4:3])
        2'b00:   hit[i] = 1'b0;
        2'b01:   hit[i] = ge_prev[i] && lt[i];
        2'b10:   hit[i] = (a54 == enc);
        default: hit[i] = ((a54 ^ enc) & ~napot_mask) == 54'd0;
      endcase
      if ((priv == PRIV_M) && !pmpcfg_q[i][7]) perm[i] = 1'b1;
      else if (acc == 2'd0) perm[i] = pmpcfg_q[i][0];
      else if (acc == 2'd1) perm[i] = pmpcfg_q[i][1];
      else if (acc == 2'd3) perm[i] = pmpcfg_q[i][0] && pmpcfg_q[i][2];
      else                  perm[i] = pmpcfg_q[i][2];
    end
    for (int i = 0; i < 16; i++) first[i] = hit[i] && ((hit & ((16'd1 << i) - 16'd1)) == 16'd0);
    return ((priv == PRIV_M) && (hit == 16'd0)) || |(first & perm);
  endfunction

  // Proposed FPGA_TIMING form with the 3ae351d rule: the second word
  // a54o = a54 + 1 (8-byte accesses are 8-byte aligned) reuses the
  // magnitude compares (a54o < x iff a54 < x and x != a54o) and adds
  // one 54-bit equality per entry (eqo), shared by NA4 and both TOR
  // bounds (entry i-1's eqo is entry i's lower bound).
  function automatic logic par_new(input logic [63:0] addr, input logic [1:0] acc, input logic [1:0] priv, input logic wide);
    logic [53:0] a54, a54o, enc, napot_mask;
    logic [15:0] lt, eqo, ge_prev, ge_prev_o, hit, hit_o, any, part, perm, first;
    a54 = addr[55:2];
    a54o = {addr[55:3], 1'b1};
    for (int i = 0; i < 16; i++) begin
      lt[i] = (a54 < pmpaddr_q[i][53:0]);
      eqo[i] = (pmpaddr_q[i][53:0] == a54o);
    end
    ge_prev[0] = 1'b1;
    ge_prev_o[0] = 1'b1;
    for (int i = 1; i < 16; i++) begin
      ge_prev[i] = !lt[i-1];
      ge_prev_o[i] = !lt[i-1] || eqo[i-1];
    end
    for (int i = 0; i < 16; i++) begin
      enc = pmpaddr_q[i][53:0];
      napot_mask = enc ^ (enc + 54'd1);
      unique case (pmpcfg_q[i][4:3])
        2'b00: begin hit[i] = 1'b0; hit_o[i] = 1'b0; end
        2'b01: begin
          hit[i] = ge_prev[i] && lt[i];
          hit_o[i] = ge_prev_o[i] && lt[i] && !eqo[i];
        end
        2'b10: begin hit[i] = (a54 == enc); hit_o[i] = eqo[i]; end
        default: begin
          hit[i] = ((a54 ^ enc) & ~napot_mask) == 54'd0;
          hit_o[i] = hit[i];
        end
      endcase
      if ((priv == PRIV_M) && !pmpcfg_q[i][7]) perm[i] = 1'b1;
      else if (acc == 2'd0) perm[i] = pmpcfg_q[i][0];
      else if (acc == 2'd1) perm[i] = pmpcfg_q[i][1];
      else if (acc == 2'd3) perm[i] = pmpcfg_q[i][0] && pmpcfg_q[i][2];
      else                  perm[i] = pmpcfg_q[i][2];
    end
    any = hit | (wide ? hit_o : 16'd0);
    part = wide ? (hit ^ hit_o) : 16'd0;
    for (int i = 0; i < 16; i++) first[i] = any[i] && ((any & ((16'd1 << i) - 16'd1)) == 16'd0);
    return ((priv == PRIV_M) && (any == 16'd0)) || |(first & perm & ~part);
  endfunction

  always_comb begin
    unique case (FORM)
      0: allow = ser_old(addr, acc, priv);
      1: allow = ser_new(addr, acc, priv, wide);
      2: allow = par_old(addr, acc, priv);
      default: allow = par_new(addr, acc, priv, wide);
    endcase
  end
endmodule
