module pmp_char (
    input  logic [127:0]  cfg_flat,
    input  logic [1023:0] addr_flat,
    input  logic [63:0]   addr,
    input  logic [1:0]    acc,
    input  logic [1:0]    priv,
    input  logic          wide,
    input  logic [7:0]    one_cfg,
    input  logic [63:0]   one_pa,
    input  logic [63:0]   one_prev,
    output logic          ok_match,
    output logic          ok_narrow,
    output logic          ok_wide_nosplit,
    output logic          ok_wide_split,
    output logic          diff_wide,
    output logic          bad_match,
    output logic          bad_narrow,
    output logic          bad_wide_nosplit,
    output logic          bad_wide_split
);
  localparam logic [1:0] PRIV_U = 2'b00, PRIV_S = 2'b01, PRIV_M = 2'b11;
  // Packed here (sigil_csr: unpacked [0:15]); pmpcfg_q[i] / pmpaddr_q[i]
  // index the same way, entry i at cfg_flat[i*8 +: 8] / addr_flat[i*64 +: 64].
  logic [15:0][7:0]  pmpcfg_q;
  logic [15:0][63:0] pmpaddr_q;
  assign pmpcfg_q = cfg_flat;
  assign pmpaddr_q = addr_flat;
  // ---- main 9da0006 (verbatim, renamed) ----
  function automatic logic pmp_match_old(
      input logic [63:0] addr,
      input logic [7:0]  cfg,
      input logic [63:0] pmpaddr,
      input logic [63:0] prev_pmpaddr);
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
  /*verilator lint_on UNUSEDSIGNAL*/
  function automatic logic pmp_check_old(
      input logic [63:0] addr,
      input logic [1:0]  acc,
      input logic [1:0]  priv);
    logic allow;
    allow = (priv == PRIV_M);
    for (int i = 15; i >= 0; i--) begin
      if (pmp_match_old(addr, pmpcfg_q[i], pmpaddr_q[i],
                    (i == 0) ? 64'd0 : pmpaddr_q[i-1])) begin
        if ((priv == PRIV_M) && !pmpcfg_q[i][7]) begin
          allow = 1'b1;
        end else if (acc == 2'd0) begin
          allow = pmpcfg_q[i][0];
        end else if (acc == 2'd1) begin
          allow = pmpcfg_q[i][1];
        end else if (acc == 2'd3) begin
          allow = pmpcfg_q[i][0] && pmpcfg_q[i][2];   
        end else begin
          allow = pmpcfg_q[i][2];
        end
      end
    end
    return allow;
  endfunction

  // ---- branch (verbatim) ----
  function automatic logic [1:0] pmp_match(
      input logic [63:0] addr,
      input logic [7:0]  cfg,
      input logic [63:0] pmpaddr,
      input logic [63:0] prev_pmpaddr);
    logic [53:0] a54, a54o, enc, prev, napot_mask;
    logic lo, hi, m;
    a54 = addr[55:2];
    a54o = {addr[55:3], 1'b1};
    enc = pmpaddr[53:0];
    prev = prev_pmpaddr[53:0];
    napot_mask = enc ^ (enc + 54'd1);   
    unique case (cfg[4:3])
      2'b00:   pmp_match = 2'b00;                                    
      2'b01: begin                                                   
        lo = (a54 >= prev);
        hi = (a54 < enc);
        pmp_match = {(lo || (prev == a54o)) && hi && (enc != a54o), lo && hi};
      end
      2'b10:   pmp_match = {a54o == enc, a54 == enc};                
      default: begin                                                 
        m = ((a54 ^ enc) & ~napot_mask) == 54'd0;
        pmp_match = {m, m};
      end
    endcase
  endfunction
  /*verilator lint_on UNUSEDSIGNAL*/
  function automatic logic pmp_check(
      input logic [63:0] addr,
      input logic [1:0]  acc,
      input logic [1:0]  priv,
      input logic        wide);
    logic allow;
    logic [1:0] m;
    allow = (priv == PRIV_M);
    for (int i = 15; i >= 0; i--) begin
      m = pmp_match(addr, pmpcfg_q[i], pmpaddr_q[i],
                    (i == 0) ? 64'd0 : pmpaddr_q[i-1]);
      if (m[0] || (wide && m[1])) begin
        if (wide && (m[0] != m[1])) begin
          allow = 1'b0;
        end else if ((priv == PRIV_M) && !pmpcfg_q[i][7]) begin
          allow = 1'b1;
        end else if (acc == 2'd0) begin
          allow = pmpcfg_q[i][0];
        end else if (acc == 2'd1) begin
          allow = pmpcfg_q[i][1];
        end else if (acc == 2'd3) begin
          allow = pmpcfg_q[i][0] && pmpcfg_q[i][2];   
        end else begin
          allow = pmpcfg_q[i][2];
        end
      end
    end
    return allow;
  endfunction

  // ---- properties ----
  logic aligned;
  assign aligned = (addr[2:0] == 3'b000);
  logic n_new, n_old;
  assign n_new = pmp_check(addr, acc, priv, wide);
  assign n_old = pmp_check_old(addr, acc, priv);
  assign ok_match = !aligned ||
      (pmp_match(addr, one_cfg, one_pa, one_prev) ==
       {pmp_match_old(addr | 64'd4, one_cfg, one_pa, one_prev),
         pmp_match_old(addr, one_cfg, one_pa, one_prev)});
  assign ok_narrow = wide || (n_new == n_old);
  // Lowest-numbered entry matching either word (main's matcher): split?
  logic split;
  always_comb begin
    logic h0, h1;
    split = 1'b0;
    for (int i = 15; i >= 0; i--) begin
      h0 = pmp_match_old(addr, pmpcfg_q[i], pmpaddr_q[i],
                         (i == 0) ? 64'd0 : pmpaddr_q[i-1]);
      h1 = pmp_match_old(addr | 64'd4, pmpcfg_q[i], pmpaddr_q[i],
                         (i == 0) ? 64'd0 : pmpaddr_q[i-1]);
      if (h0 || h1) split = (h0 != h1);
    end
  end
  assign ok_wide_nosplit = !(wide && aligned && !split) || (n_new == n_old);
  assign ok_wide_split = !(wide && aligned && split) || !n_new;
  assign diff_wide = wide && aligned && (n_new != n_old);
  // Miter outputs for ABC (constant 0 iff the property holds).
  assign bad_match = !ok_match;
  assign bad_narrow = !ok_narrow;
  assign bad_wide_nosplit = !ok_wide_nosplit;
  assign bad_wide_split = !ok_wide_split;
endmodule
