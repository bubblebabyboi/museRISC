// Sigil in-house core: RV64C decompressor (Zca + Zcb +
// Zcd). Expands a 16-bit parcel to its canonical 32-bit
// encoding so the main decoder sees one instruction format.
// Reserved/hint rules follow the C spec: c.addi4spn with a
// zero immediate, c.lui/c.addi16sp with a zero immediate,
// c.addiw with rd=x0, c.lwsp/c.ldsp with rd=x0, c.jr with
// rs1=x0, and the reserved W-form/Zcb slots are illegal;
// rd=x0 forms that are defined hints expand as usual (their
// write to x0 is discarded downstream).

/* verilator lint_off UNUSEDSIGNAL */
module sigil_rvc (
    input  logic [15:0] in_i,
    output logic [31:0] out_o,
    output logic        illegal_o
);

  // canonical encoders
  function automatic logic [31:0] enc_i(
      input logic [11:0] imm12, input logic [4:0] rs1,
      input logic [2:0] f3, input logic [4:0] rd,
      input logic [6:0] opc);
    return {imm12, rs1, f3, rd, opc};
  endfunction
  function automatic logic [31:0] enc_r(
      input logic [6:0] f7, input logic [4:0] rs2,
      input logic [4:0] rs1, input logic [2:0] f3,
      input logic [4:0] rd, input logic [6:0] opc);
    return {f7, rs2, rs1, f3, rd, opc};
  endfunction
  function automatic logic [31:0] enc_s(
      input logic [11:0] imm12, input logic [4:0] rs2,
      input logic [4:0] rs1, input logic [2:0] f3,
      input logic [6:0] opc);
    return {imm12[11:5], rs2, rs1, f3, imm12[4:0], opc};
  endfunction
  function automatic logic [31:0] enc_b(
      input logic [12:0] imm13, input logic [4:0] rs2,
      input logic [4:0] rs1, input logic [2:0] f3);
    return {imm13[12], imm13[10:5], rs2, rs1, f3, imm13[4:1],
            imm13[11], 7'b1100011};
  endfunction
  function automatic logic [31:0] enc_u(
      input logic [19:0] imm20, input logic [4:0] rd,
      input logic [6:0] opc);
    return {imm20, rd, opc};
  endfunction
  function automatic logic [31:0] enc_j(
      input logic [20:0] imm21, input logic [4:0] rd);
    return {imm21[20], imm21[10:1], imm21[11], imm21[19:12], rd,
            7'b1101111};
  endfunction

  always_comb begin
    logic [4:0] rdp, rs1p, rs2p, rd, rs1, rs2;
    logic [11:0] imm;
    logic [5:0] imm6;
    rdp  = {2'b01, in_i[4:2]};
    rs1p = {2'b01, in_i[9:7]};
    rs2p = {2'b01, in_i[4:2]};
    rd   = in_i[11:7];
    rs1  = in_i[11:7];
    rs2  = in_i[6:2];
    imm6 = {in_i[12], in_i[6:2]};
    imm  = 12'b0;
    out_o = 32'b0;
    illegal_o = 1'b0;

    unique case (in_i[1:0])
      2'b00: begin
        unique case (in_i[15:13])
          3'b000: begin  // c.addi4spn
            imm = {2'b0, in_i[10:7], in_i[12:11], in_i[5],
                   in_i[6], 2'b0};
            if (imm == 12'b0) illegal_o = 1'b1;
            out_o = enc_i(imm, 5'd2, 3'b000, rdp, 7'b0010011);
          end
          3'b001: begin  // c.fld (Zcd)
            imm = {4'b0, in_i[6], in_i[5], in_i[12:10], 3'b0};
            out_o = enc_i(imm, rs1p, 3'b011, rdp, 7'b0000111);
          end
          3'b010: begin  // c.lw
            imm = {5'b0, in_i[5], in_i[12:10], in_i[6], 2'b0};
            out_o = enc_i(imm, rs1p, 3'b010, rdp, 7'b0000011);
          end
          3'b011: begin  // c.ld
            imm = {4'b0, in_i[6], in_i[5], in_i[12:10], 3'b0};
            out_o = enc_i(imm, rs1p, 3'b011, rdp, 7'b0000011);
          end
          3'b100: begin  // Zcb loads/stores
            unique case (in_i[12:10])
              3'b000: begin  // c.lbu: imm = {i5, i6}
                imm = {10'b0, in_i[5], in_i[6]};
                out_o = enc_i(imm, rs1p, 3'b100, rdp, 7'b0000011);
              end
              3'b001: begin  // c.lhu (i6=0) / c.lh (i6=1), imm={i5,0}
                imm = {10'b0, in_i[5], 1'b0};
                out_o = enc_i(imm, rs1p, in_i[6] ? 3'b001 : 3'b101,
                              rdp, 7'b0000011);
              end
              3'b010: begin  // c.sb
                imm = {10'b0, in_i[5], in_i[6]};
                out_o = enc_s(imm, rdp, rs1p, 3'b000, 7'b0100011);
              end
              3'b011: begin  // c.sh (i6 must be 0)
                imm = {10'b0, in_i[5], 1'b0};
                if (in_i[6]) illegal_o = 1'b1;
                out_o = enc_s(imm, rdp, rs1p, 3'b001, 7'b0100011);
              end
              default: illegal_o = 1'b1;
            endcase
          end
          3'b101: begin  // c.fsd (Zcd)
            imm = {4'b0, in_i[6], in_i[5], in_i[12:10], 3'b0};
            out_o = enc_s(imm, rdp, rs1p, 3'b011, 7'b0100111);
          end
          3'b110: begin  // c.sw
            imm = {5'b0, in_i[5], in_i[12:10], in_i[6], 2'b0};
            out_o = enc_s(imm, rdp, rs1p, 3'b010, 7'b0100011);
          end
          3'b111: begin  // c.sd
            imm = {4'b0, in_i[6], in_i[5], in_i[12:10], 3'b0};
            out_o = enc_s(imm, rdp, rs1p, 3'b011, 7'b0100011);
          end
          default: illegal_o = 1'b1;
        endcase
      end

      2'b01: begin
        unique case (in_i[15:13])
          3'b000: begin  // c.addi (rd=x0 is the nop encoding)
            out_o = enc_i({{6{imm6[5]}}, imm6}, rd, 3'b000, rd,
                          7'b0010011);
          end
          3'b001: begin  // c.addiw (rd=x0 reserved)
            if (rd == 5'd0) illegal_o = 1'b1;
            out_o = enc_i({{6{imm6[5]}}, imm6}, rd, 3'b000, rd,
                          7'b0011011);
          end
          3'b010: begin  // c.li
            out_o = enc_i({{6{imm6[5]}}, imm6}, 5'd0, 3'b000, rd,
                          7'b0010011);
          end
          3'b011: begin
            if (rd == 5'd2) begin  // c.addi16sp
              imm = {{3{in_i[12]}}, in_i[4:3], in_i[5], in_i[2],
                     in_i[6], 4'b0};
              if (imm == 12'b0) illegal_o = 1'b1;
              out_o = enc_i(imm, 5'd2, 3'b000, 5'd2, 7'b0010011);
            end else begin          // c.lui
              if (imm6 == 6'b0) illegal_o = 1'b1;
              out_o = enc_u({{14{imm6[5]}}, imm6}, rd, 7'b0110111);
            end
          end
          3'b100: begin
            unique case (in_i[11:10])
              2'b00:  // c.srli
                out_o = enc_i({6'b0, imm6}, rs1p, 3'b101, rs1p,
                              7'b0010011);
              2'b01:  // c.srai
                out_o = enc_i({6'b010000, imm6}, rs1p, 3'b101, rs1p,
                              7'b0010011);
              2'b10:  // c.andi
                out_o = enc_i({{6{imm6[5]}}, imm6}, rs1p, 3'b111,
                              rs1p, 7'b0010011);
              2'b11: begin
                if (!in_i[12]) begin
                  unique case (in_i[6:5])
                    2'b00: out_o = enc_r(7'b0100000, rs2p, rs1p,
                                         3'b000, rs1p, 7'b0110011);
                    2'b01: out_o = enc_r(7'b0000000, rs2p, rs1p,
                                         3'b100, rs1p, 7'b0110011);
                    2'b10: out_o = enc_r(7'b0000000, rs2p, rs1p,
                                         3'b110, rs1p, 7'b0110011);
                    2'b11: out_o = enc_r(7'b0000000, rs2p, rs1p,
                                         3'b111, rs1p, 7'b0110011);
                  endcase
                end else begin
                  unique case (in_i[6:5])
                    2'b00: out_o = enc_r(7'b0100000, rs2p, rs1p,
                                         3'b000, rs1p, 7'b0111011);
                    2'b01: out_o = enc_r(7'b0000000, rs2p, rs1p,
                                         3'b000, rs1p, 7'b0111011);
                    2'b10: out_o = enc_r(7'b0000001, rs2p, rs1p,
                                         3'b000, rs1p, 7'b0110011);
                    2'b11: begin  // Zcb unary ops by [4:2]
                      unique case (in_i[4:2])
                        3'b000:  // c.zext.b -> andi rd, rd, 255
                          out_o = enc_i(12'd255, rs1p, 3'b111, rs1p,
                                        7'b0010011);
                        3'b001:  // c.sext.b
                          out_o = enc_i(12'b011000000100, rs1p,
                                        3'b001, rs1p, 7'b0010011);
                        3'b010:  // c.zext.h -> packw rd, rd, x0
                          out_o = enc_r(7'b0000100, 5'd0, rs1p,
                                        3'b100, rs1p, 7'b0111011);
                        3'b011:  // c.sext.h
                          out_o = enc_i(12'b011000000101, rs1p,
                                        3'b001, rs1p, 7'b0010011);
                        3'b100:  // c.zext.w -> add.uw rd, rd, x0
                          out_o = enc_r(7'b0000100, 5'd0, rs1p,
                                        3'b000, rs1p, 7'b0111011);
                        3'b101:  // c.not -> xori rd, rd, -1
                          out_o = enc_i(12'hFFF, rs1p, 3'b100, rs1p,
                                        7'b0010011);
                        default: illegal_o = 1'b1;
                      endcase
                    end
                  endcase
                end
              end
              default: illegal_o = 1'b1;
            endcase
          end
          3'b101: begin  // c.j
            out_o = enc_j({{9{in_i[12]}}, in_i[12], in_i[8],
                           in_i[10:9], in_i[6], in_i[7], in_i[2],
                           in_i[11], in_i[5:3], 1'b0}, 5'd0);
          end
          3'b110, 3'b111: begin  // c.beqz / c.bnez
            out_o = enc_b({{5{in_i[12]}}, in_i[6:5], in_i[2],
                           in_i[11:10], in_i[4:3], 1'b0}, 5'd0, rs1p,
                          in_i[13] ? 3'b001 : 3'b000);
          end
          default: illegal_o = 1'b1;
        endcase
      end

      2'b10: begin
        unique case (in_i[15:13])
          3'b000: begin  // c.slli (rd=x0 hint)
            out_o = enc_i({6'b0, imm6}, rd, 3'b001, rd, 7'b0010011);
          end
          3'b001: begin  // c.fldsp (Zcd)
            imm = {3'b0, in_i[4:2], in_i[12], in_i[6:5], 3'b0};
            out_o = enc_i(imm, 5'd2, 3'b011, rd, 7'b0000111);
          end
          3'b010: begin  // c.lwsp (rd=x0 reserved)
            if (rd == 5'd0) illegal_o = 1'b1;
            imm = {4'b0, in_i[3:2], in_i[12], in_i[6:4], 2'b0};
            out_o = enc_i(imm, 5'd2, 3'b010, rd, 7'b0000011);
          end
          3'b011: begin  // c.ldsp (rd=x0 reserved)
            if (rd == 5'd0) illegal_o = 1'b1;
            imm = {3'b0, in_i[4:2], in_i[12], in_i[6:5], 3'b0};
            out_o = enc_i(imm, 5'd2, 3'b011, rd, 7'b0000011);
          end
          3'b100: begin
            if (!in_i[12]) begin
              if (rs2 == 5'd0) begin  // c.jr (rs1=x0 reserved)
                if (rs1 == 5'd0) illegal_o = 1'b1;
                out_o = enc_i(12'b0, rs1, 3'b000, 5'd0, 7'b1100111);
              end else begin          // c.mv
                out_o = enc_r(7'b0, rs2, 5'd0, 3'b000, rd,
                              7'b0110011);
              end
            end else begin
              if (rs2 == 5'd0) begin
                if (rd == 5'd0) begin  // c.ebreak
                  out_o = 32'h0010_0073;
                end else begin         // c.jalr
                  out_o = enc_i(12'b0, rs1, 3'b000, 5'd1,
                                7'b1100111);
                end
              end else begin           // c.add
                out_o = enc_r(7'b0, rs2, rs1, 3'b000, rd,
                              7'b0110011);
              end
            end
          end
          3'b101: begin  // c.fsdsp (Zcd)
            imm = {3'b0, in_i[9:7], in_i[12:10], 3'b0};
            out_o = enc_s(imm, rs2, 5'd2, 3'b011, 7'b0100111);
          end
          3'b110: begin  // c.swsp
            imm = {4'b0, in_i[8:7], in_i[12:9], 2'b0};
            out_o = enc_s(imm, rs2, 5'd2, 3'b010, 7'b0100011);
          end
          3'b111: begin  // c.sdsp
            imm = {3'b0, in_i[9:7], in_i[12:10], 3'b0};
            out_o = enc_s(imm, rs2, 5'd2, 3'b011, 7'b0100011);
          end
          default: illegal_o = 1'b1;
        endcase
      end

      default: illegal_o = 1'b1;  // quadrant 11 is not 16-bit
    endcase
  end

endmodule
