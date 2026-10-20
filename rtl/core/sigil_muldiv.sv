// RV64M multiply/divide unit (stage 2), combinational.
// funct3 selects: 000 MUL, 001 MULH, 010 MULHSU, 011 MULHU,
// 100 DIV, 101 DIVU, 110 REM, 111 REMU. word_op_i applies the
// 32-bit W-variant rule (low 32-bit operands, sign-extended result;
// MULW is the only word multiply).
//
// Spec edge cases (RV64M): division by zero yields quotient = all
// ones and remainder = dividend; signed overflow (most negative /
// -1) yields quotient = dividend and remainder 0. Signed division
// truncates toward zero; the remainder takes the dividend's sign.
//
// A combinational divider will not close timing in a real flow;
// it is the stage-2 correctness vehicle. An iterative divider with
// an EX stall replaces it before any synthesis target (docs/CORE.md).
`default_nettype none
module sigil_muldiv (
    input  wire [2:0]  funct3_i,
    input  wire        word_op_i,
    input  wire [63:0] a_i,
    input  wire [63:0] b_i,
    output logic [63:0] result_o
);
  // ---- widen to the working width (32 or 64 bits) -----------------
  logic [63:0] a64, b64;
  assign a64 = word_op_i ? {{32{a_i[31]}}, a_i[31:0]} : a_i;
  assign b64 = word_op_i ? {{32{b_i[31]}}, b_i[31:0]} : b_i;

  // Mask that keeps the working-width result (sign-extends at the end
  // for word ops; see result mux). For word ops the operand values
  // themselves are the sign-extended 32-bit values, which makes the
  // 32-bit and 64-bit signed results agree in the low bits and in
  // the quotient/remainder signs.
  logic [63:0] a_val, b_val;
  assign a_val = word_op_i ? a64 : a_i;
  assign b_val = word_op_i ? b64 : b_i;
  // Unsigned views at working width (zero-extended for word ops).
  logic [63:0] au, bu;
  assign au = word_op_i ? {32'd0, a_i[31:0]} : a_i;
  assign bu = word_op_i ? {32'd0, b_i[31:0]} : b_i;

  // ---- products ---------------------------------------------------
  // Low halves of the signed products are intentionally unused:
  // MUL takes its low half from the unsigned product (identical bits).
  /* verilator lint_off UNUSEDSIGNAL */
  logic signed [127:0] a_s128, b_s128, prod_ss, prod_su;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [127:0] prod_uu;
  assign a_s128 = {{64{a_val[63]}}, a_val};
  assign b_s128 = {{64{b_val[63]}}, b_val};
  assign prod_ss = a_s128 * b_s128;
  assign prod_su = a_s128 * $signed({64'd0, bu});
  assign prod_uu = {64'd0, au} * {64'd0, bu};

  // ---- division by magnitudes --------------------------------------
  logic        is_div, is_rem, signed_div;
  logic [63:0] a_mag, b_mag, quot_mag, rem_mag, quot, rem;
  logic        neg_quot, neg_rem, div_zero, overflow;
  logic [63:0] most_neg;

  assign is_div = (funct3_i[2:1] == 2'b10);
  assign is_rem = (funct3_i[2:1] == 2'b11);
  assign signed_div = !funct3_i[0];  // DIV/REM signed, DIVU/REMU not
  assign most_neg = word_op_i ? 64'hFFFF_FFFF_8000_0000
                              : 64'h8000_0000_0000_0000;
  assign div_zero = (bu == 64'd0);
  assign overflow = signed_div && (a_val == most_neg) &&
                    (b_val == 64'hFFFF_FFFF_FFFF_FFFF);
  assign a_mag = (signed_div && a_val[63]) ? (~a_val + 64'd1) : au;
  assign b_mag = (signed_div && b_val[63]) ? (~b_val + 64'd1) : bu;
  assign quot_mag = div_zero ? 64'd0 : (a_mag / b_mag);
  assign rem_mag = div_zero ? 64'd0 : (a_mag % b_mag);
  assign neg_quot = signed_div && (a_val[63] != b_val[63]);
  assign neg_rem = signed_div && a_val[63];

  always_comb begin
    if (div_zero) begin
      quot = word_op_i ? 64'hFFFF_FFFF_FFFF_FFFF : 64'hFFFF_FFFF_FFFF_FFFF;
      rem = a_val;
    end else if (overflow) begin
      quot = a_val;
      rem = 64'd0;
    end else begin
      quot = neg_quot ? (~quot_mag + 64'd1) : quot_mag;
      rem = neg_rem ? (~rem_mag + 64'd1) : rem_mag;
    end
  end

  // ---- result select ------------------------------------------------
  logic [63:0] result64;
  always_comb begin
    if (is_div) begin
      result64 = quot;
    end else if (is_rem) begin
      result64 = rem;
    end else begin
      unique case (funct3_i)
        3'b000:  result64 = prod_uu[63:0];    // MUL (low, sign-agnostic)
        3'b001:  result64 = prod_ss[127:64];  // MULH
        3'b010:  result64 = prod_su[127:64];  // MULHSU
        default: result64 = prod_uu[127:64];  // MULHU
      endcase
    end
  end

  // Word results: MULW keeps the low 32 bits of the product;
  // DIVW/DIVUW/REMW/REMUW were computed on sign/zero-extended
  // 32-bit operands above, so the low 32 bits already hold the
  // 32-bit quotient/remainder; sign-extend per the W rule. The
  // divide-by-zero word quotient is -1, i.e. all 64 bits set
  // after sign extension, matching the non-word constant.
  assign result_o = word_op_i ? {{32{result64[31]}}, result64[31:0]}
                              : result64;
endmodule
`default_nettype wire
