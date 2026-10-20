// RV64I ALU with a total specification in both widths: with
// word_op_i set, every operation is performed on the low 32 bits
// and the result sign-extended (the W-variant rule), including
// compares. The decoder only requests word mode for the encodings
// that have W variants, but keeping the module total makes it
// unit-testable in isolation.
`default_nettype none
module sigil_alu import sigil_pkg::*; (
    input  sigil_pkg::alu_op_e op_i,
    input  wire                    word_op_i,
    input  wire [63:0]             a_i,
    input  wire [63:0]             b_i,
    output logic [63:0]            result_o
);
  logic [63:0] result64;
  logic [31:0] result32;

  always_comb begin
    unique case (op_i)
      ALU_ADD:    result64 = a_i + b_i;
      ALU_SUB:    result64 = a_i - b_i;
      ALU_SLL:    result64 = a_i << b_i[5:0];
      ALU_SLT:    result64 = ($signed(a_i) < $signed(b_i)) ? 64'd1 : 64'd0;
      ALU_SLTU:   result64 = (a_i < b_i) ? 64'd1 : 64'd0;
      ALU_XOR:    result64 = a_i ^ b_i;
      ALU_SRL:    result64 = a_i >> b_i[5:0];
      ALU_SRA:    result64 = $unsigned($signed(a_i) >>> b_i[5:0]);
      ALU_OR:     result64 = a_i | b_i;
      ALU_AND:    result64 = a_i & b_i;
      ALU_COPY_B: result64 = b_i;
      default:    result64 = 64'd0;
    endcase
  end

  always_comb begin
    unique case (op_i)
      ALU_ADD:    result32 = a_i[31:0] + b_i[31:0];
      ALU_SUB:    result32 = a_i[31:0] - b_i[31:0];
      ALU_SLL:    result32 = a_i[31:0] << b_i[4:0];
      ALU_SLT:    result32 = ($signed(a_i[31:0]) < $signed(b_i[31:0])) ? 32'd1 : 32'd0;
      ALU_SLTU:   result32 = (a_i[31:0] < b_i[31:0]) ? 32'd1 : 32'd0;
      ALU_XOR:    result32 = a_i[31:0] ^ b_i[31:0];
      ALU_SRL:    result32 = a_i[31:0] >> b_i[4:0];
      ALU_SRA:    result32 = $unsigned($signed(a_i[31:0]) >>> b_i[4:0]);
      ALU_OR:     result32 = a_i[31:0] | b_i[31:0];
      ALU_AND:    result32 = a_i[31:0] & b_i[31:0];
      ALU_COPY_B: result32 = b_i[31:0];
      default:    result32 = 32'd0;
    endcase
  end

  assign result_o = word_op_i ? {{32{result32[31]}}, result32} : result64;
endmodule
`default_nettype wire
