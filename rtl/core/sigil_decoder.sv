// RV64I decoder (stage 1): full base integer set. FENCE* decode as
// NOPs; ECALL/EBREAK raise the corresponding trap in the core.
// Anything else (including all CSR instructions until stage 3) is
// marked illegal so the core traps instead of silently misexecuting.
`default_nettype none
module sigil_decoder import sigil_pkg::*; (
    input  wire [31:0]          instr_i,
    output sigil_pkg::ctrl_t ctrl_o,
    output logic [63:0]         imm_o,
    output logic [4:0]          rs1_o,
    output logic [4:0]          rs2_o,
    output logic [4:0]          rd_o
);
  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  logic [63:0] imm_i, imm_s, imm_b, imm_u, imm_j;

  assign opcode = instr_i[6:0];
  assign funct3 = instr_i[14:12];
  assign funct7 = instr_i[31:25];
  assign rs1_o  = instr_i[19:15];
  assign rs2_o  = instr_i[24:20];
  assign rd_o   = instr_i[11:7];

  assign imm_i = {{52{instr_i[31]}}, instr_i[31:20]};
  assign imm_s = {{52{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
  assign imm_b = {{51{instr_i[31]}}, instr_i[31], instr_i[7],
                  instr_i[30:25], instr_i[11:8], 1'b0};
  assign imm_u = {{32{instr_i[31]}}, instr_i[31:12], 12'd0};
  assign imm_j = {{43{instr_i[31]}}, instr_i[31], instr_i[19:12],
                  instr_i[20], instr_i[30:21], 1'b0};

  // OP/OP-IMM ALU select from funct3 (+ funct7 for SUB/SRA).
  function automatic alu_op_e alu_decode(input logic [2:0] f3,
                                         input logic alt);
    unique case (f3)
      3'b000:  alu_decode = alt ? ALU_SUB : ALU_ADD;
      3'b001:  alu_decode = ALU_SLL;
      3'b010:  alu_decode = ALU_SLT;
      3'b011:  alu_decode = ALU_SLTU;
      3'b100:  alu_decode = ALU_XOR;
      3'b101:  alu_decode = alt ? ALU_SRA : ALU_SRL;
      3'b110:  alu_decode = ALU_OR;
      default: alu_decode = ALU_AND;
    endcase
  endfunction

  always_comb begin
    ctrl_o = '0;
    ctrl_o.alu_op = ALU_ADD;
    ctrl_o.funct3 = funct3;
    imm_o = imm_i;

    unique case (opcode)
      7'b0110111: begin  // LUI
        ctrl_o.valid = 1'b1;
        ctrl_o.reg_write = 1'b1;
        ctrl_o.alu_src_imm = 1'b1;
        ctrl_o.alu_op = ALU_COPY_B;
        imm_o = imm_u;
      end
      7'b0010111: begin  // AUIPC
        ctrl_o.valid = 1'b1;
        ctrl_o.reg_write = 1'b1;
        ctrl_o.alu_src_imm = 1'b1;
        ctrl_o.alu_a_pc = 1'b1;
        ctrl_o.alu_op = ALU_ADD;
        imm_o = imm_u;
      end
      7'b1101111: begin  // JAL
        ctrl_o.valid = 1'b1;
        ctrl_o.reg_write = 1'b1;
        ctrl_o.jal = 1'b1;
        imm_o = imm_j;
      end
      7'b1100111: begin  // JALR (funct3 must be 000)
        if (funct3 == 3'b000) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.reg_write = 1'b1;
          ctrl_o.jalr = 1'b1;
          imm_o = imm_i;
        end
      end
      7'b1100011: begin  // branches
        if ((funct3 != 3'b010) && (funct3 != 3'b011)) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.branch = 1'b1;
          imm_o = imm_b;
        end
      end
      7'b0000011: begin  // loads (funct3 000..110)
        if (funct3 != 3'b111) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.reg_write = 1'b1;
          ctrl_o.mem_read = 1'b1;
          ctrl_o.alu_src_imm = 1'b1;
          imm_o = imm_i;
        end
      end
      7'b0100011: begin  // stores (funct3 000..011)
        if (funct3[2] == 1'b0) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.mem_write = 1'b1;
          ctrl_o.alu_src_imm = 1'b1;
          imm_o = imm_s;
        end
      end
      7'b0010011: begin  // OP-IMM (+ B/K unary & bit-imm ops)
        // B/K encodings live in OP-IMM space rejected by the
        // shift-immediate legality checks below; take them
        // first. bext operand B comes from imm_i[5:0] (or the
        // rcon nibble in imm_i[3:0] for aes64ks1i).
        if ((funct3 == 3'b001) && (instr_i[31:25] == 7'b0110000)) begin
          // clz/ctz/cpop/sext.b/sext.h by imm[24:20]
          unique case (instr_i[24:20])
            5'b00000: ctrl_o.bext_op = 7'd11;
            5'b00001: ctrl_o.bext_op = 7'd13;
            5'b00010: ctrl_o.bext_op = 7'd15;
            5'b00100: ctrl_o.bext_op = 7'd21;
            5'b00101: ctrl_o.bext_op = 7'd22;
            default:  ctrl_o.bext_op = 7'd63;
          endcase
          if (ctrl_o.bext_op != 7'd63) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.reg_write = 1'b1;
            ctrl_o.bext = 1'b1;
          end
        end else if (funct3 == 3'b001 &&
                     instr_i[31:25] == 7'b0011000) begin
          // aes64im (rs2 field 0) / aes64ks1i (0x10+rcon<=0x1A)
          if (instr_i[24:20] == 5'd0) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.reg_write = 1'b1;
            ctrl_o.bext = 1'b1;
            ctrl_o.bext_op = 7'd48;
          end else if (instr_i[24] && (instr_i[23:20] <= 4'hA)) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.reg_write = 1'b1;
            ctrl_o.bext = 1'b1;
            ctrl_o.bext_op = 7'd49;
            ctrl_o.alu_src_imm = 1'b1;
          end
        end else if (funct3 == 3'b001 &&
                     instr_i[31:25] == 7'b0001000) begin
          // SHA256/SHA512 unary ops by imm[24:20]
          unique case (instr_i[24:20])
            5'b00000: ctrl_o.bext_op = 7'd53;  // sha256sum0
            5'b00001: ctrl_o.bext_op = 7'd54;  // sha256sum1
            5'b00010: ctrl_o.bext_op = 7'd51;  // sha256sig0
            5'b00011: ctrl_o.bext_op = 7'd52;  // sha256sig1
            5'b00100: ctrl_o.bext_op = 7'd57;  // sha512sum0
            5'b00101: ctrl_o.bext_op = 7'd58;  // sha512sum1
            5'b00110: ctrl_o.bext_op = 7'd55;  // sha512sig0
            5'b00111: ctrl_o.bext_op = 7'd56;  // sha512sig1
            default:  ctrl_o.bext_op = 7'd63;
          endcase
          if (ctrl_o.bext_op != 7'd63) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.reg_write = 1'b1;
            ctrl_o.bext = 1'b1;
          end
        end else if (funct3 == 3'b001 &&
                     (instr_i[31:26] == 6'b010010 ||
                      instr_i[31:26] == 6'b011010 ||
                      instr_i[31:26] == 6'b001010)) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.reg_write = 1'b1;
          ctrl_o.bext = 1'b1;
          ctrl_o.alu_src_imm = 1'b1;
          ctrl_o.bext_op = (instr_i[31:26] == 6'b010010) ? 7'd32 :
                           (instr_i[31:26] == 6'b011010) ? 7'd34 : 7'd35;
        end else if (funct3 == 3'b101 &&
                     instr_i[31:26] == 6'b011000) begin
          ctrl_o.valid = 1'b1;                 // rori
          ctrl_o.reg_write = 1'b1;
          ctrl_o.bext = 1'b1;
          ctrl_o.alu_src_imm = 1'b1;
          ctrl_o.bext_op = 7'd25;
        end else if (funct3 == 3'b101 &&
                     instr_i[31:26] == 6'b010010) begin
          ctrl_o.valid = 1'b1;                 // bexti
          ctrl_o.reg_write = 1'b1;
          ctrl_o.bext = 1'b1;
          ctrl_o.alu_src_imm = 1'b1;
          ctrl_o.bext_op = 7'd33;
        end else if (funct3 == 3'b101 &&
                     (instr_i[31:20] == 12'h287 ||
                      instr_i[31:20] == 12'h687 ||
                      instr_i[31:20] == 12'h6B8)) begin
          ctrl_o.valid = 1'b1;                 // orc.b/brev8/rev8
          ctrl_o.reg_write = 1'b1;
          ctrl_o.bext = 1'b1;
          ctrl_o.bext_op = (instr_i[31:20] == 12'h287) ? 7'd27 :
                           (instr_i[31:20] == 12'h687) ? 7'd41 : 7'd28;
        end else begin
        ctrl_o.valid = 1'b1;
        ctrl_o.reg_write = 1'b1;
        ctrl_o.alu_src_imm = 1'b1;
        // instr[30] is an immediate bit here, not a funct7 bit:
        // it selects SRAI vs SRLI only. In particular ADDI is
        // always ADD, even when the immediate is negative.
        ctrl_o.alu_op = alu_decode(funct3,
                                   (funct3 == 3'b101) ? instr_i[30] : 1'b0);
        imm_o = imm_i;
        // Shift encodings with reserved imm bits set are illegal.
        if ((funct3 == 3'b001) && (instr_i[31:26] != 6'b000000)) begin
          ctrl_o.valid = 1'b0;
        end
        if ((funct3 == 3'b101) && (instr_i[31:26] != 6'b000000) &&
            (instr_i[31:26] != 6'b010000)) begin
          ctrl_o.valid = 1'b0;
        end
        end
      end
      7'b0110011: begin  // OP (register-register) and M (funct7=1)
        if ((funct7 == 7'b0000000) ||
            ((funct7 == 7'b0100000) &&
             ((funct3 == 3'b000) || (funct3 == 3'b101)))) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.reg_write = 1'b1;
          ctrl_o.alu_op = alu_decode(funct3, instr_i[30]);
        end else if (funct7 == 7'b0000001) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.reg_write = 1'b1;
          ctrl_o.muldiv = 1'b1;
        end else begin
          // B / Zicond / scalar-crypto OP space.
          ctrl_o.bext_op = 7'd63;
          unique case (funct7)
            7'b0000100: begin
              if (funct3 == 3'b100) ctrl_o.bext_op = 7'd38; // pack
              if (funct3 == 3'b111) ctrl_o.bext_op = 7'd39; // packh
            end
            7'b0000101: begin
              unique case (funct3)
                3'b001: ctrl_o.bext_op = 7'd29;  // clmul
                3'b010: ctrl_o.bext_op = 7'd31;  // clmulr
                3'b011: ctrl_o.bext_op = 7'd30;  // clmulh
                3'b100: ctrl_o.bext_op = 7'd19;  // min
                3'b101: ctrl_o.bext_op = 7'd20;  // minu
                3'b110: ctrl_o.bext_op = 7'd17;  // max
                3'b111: ctrl_o.bext_op = 7'd18;  // maxu
                default: ctrl_o.bext_op = 7'd63;
              endcase
            end
            7'b0000111: begin
              if (funct3 == 3'b101) ctrl_o.bext_op = 7'd36;
              if (funct3 == 3'b111) ctrl_o.bext_op = 7'd37;
            end
            7'b0010000: begin
              if (funct3 == 3'b010) ctrl_o.bext_op = 7'd1;
              if (funct3 == 3'b100) ctrl_o.bext_op = 7'd2;
              if (funct3 == 3'b110) ctrl_o.bext_op = 7'd3;
            end
            7'b0010100: begin
              if (funct3 == 3'b001) ctrl_o.bext_op = 7'd35; // bset
              if (funct3 == 3'b010) ctrl_o.bext_op = 7'd42; // xperm4
              if (funct3 == 3'b100) ctrl_o.bext_op = 7'd43; // xperm8
            end
            7'b0100000: begin
              if (funct3 == 3'b100) ctrl_o.bext_op = 7'd10; // xnor
              if (funct3 == 3'b110) ctrl_o.bext_op = 7'd9;  // orn
              if (funct3 == 3'b111) ctrl_o.bext_op = 7'd8;  // andn
            end
            7'b0100100: begin
              if (funct3 == 3'b001) ctrl_o.bext_op = 7'd32; // bclr
              if (funct3 == 3'b101) ctrl_o.bext_op = 7'd33; // bext
            end
            7'b0110000: begin
              if (funct3 == 3'b001) ctrl_o.bext_op = 7'd23; // rol
              if (funct3 == 3'b101) ctrl_o.bext_op = 7'd25; // ror
            end
            7'b0110100: begin
              if (funct3 == 3'b001) ctrl_o.bext_op = 7'd34; // binv
            end
            7'b0011001: if (funct3 == 3'b000) ctrl_o.bext_op = 7'd44;
            7'b0011011: if (funct3 == 3'b000) ctrl_o.bext_op = 7'd45;
            7'b0011101: if (funct3 == 3'b000) ctrl_o.bext_op = 7'd46;
            7'b0011111: if (funct3 == 3'b000) ctrl_o.bext_op = 7'd47;
            7'b0111111: if (funct3 == 3'b000) ctrl_o.bext_op = 7'd50;
            default: ctrl_o.bext_op = 7'd63;
          endcase
          if (ctrl_o.bext_op != 7'd63) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.reg_write = 1'b1;
            ctrl_o.bext = 1'b1;
          end
        end
      end
      7'b0011011: begin  // OP-IMM-32 (+ W-form B ops)
        if ((funct3 == 3'b001) && (instr_i[31:25] == 7'b0110000)) begin
          unique case (instr_i[24:20])
            5'b00000: ctrl_o.bext_op = 7'd12;  // clzw
            5'b00001: ctrl_o.bext_op = 7'd14;  // ctzw
            5'b00010: ctrl_o.bext_op = 7'd16;  // cpopw
            default:  ctrl_o.bext_op = 7'd63;
          endcase
          if (ctrl_o.bext_op != 7'd63) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.reg_write = 1'b1;
            ctrl_o.bext = 1'b1;
          end
        end else if ((funct3 == 3'b001) &&
                     (instr_i[31:26] == 6'b000010)) begin
          ctrl_o.valid = 1'b1;                 // slli.uw
          ctrl_o.reg_write = 1'b1;
          ctrl_o.bext = 1'b1;
          ctrl_o.alu_src_imm = 1'b1;
          ctrl_o.bext_op = 7'd7;
          imm_o = imm_i;
        end else if ((funct3 == 3'b101) &&
                     (instr_i[31:25] == 7'b0110000)) begin
          ctrl_o.valid = 1'b1;                 // roriw
          ctrl_o.reg_write = 1'b1;
          ctrl_o.bext = 1'b1;
          ctrl_o.alu_src_imm = 1'b1;
          ctrl_o.bext_op = 7'd26;
          imm_o = imm_i;
        end else begin
        ctrl_o.valid = 1'b1;
        ctrl_o.reg_write = 1'b1;
        ctrl_o.alu_src_imm = 1'b1;
        ctrl_o.word_op = 1'b1;
        // As OP-IMM: instr[30] is an immediate bit; ADDIW is ADD.
        ctrl_o.alu_op = alu_decode(funct3,
                                   (funct3 == 3'b101) ? instr_i[30] : 1'b0);
        imm_o = imm_i;
        if ((funct3 != 3'b000) && (funct3 != 3'b001) &&
            (funct3 != 3'b101)) begin
          ctrl_o.valid = 1'b0;
        end
        if ((funct3 == 3'b001) && (funct7 != 7'b0000000)) begin
          ctrl_o.valid = 1'b0;
        end
        if ((funct3 == 3'b101) && (funct7 != 7'b0000000) &&
            (funct7 != 7'b0100000)) begin
          ctrl_o.valid = 1'b0;
        end
        end
      end
      7'b0111011: begin  // OP-32 and M W-variants (funct7=1)
        ctrl_o.word_op = 1'b1;
        ctrl_o.alu_op = alu_decode(funct3, instr_i[30]);
        if ((funct7 == 7'b0000000) &&
            ((funct3 == 3'b000) || (funct3 == 3'b001) ||
             (funct3 == 3'b101))) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.reg_write = 1'b1;
        end else if ((funct7 == 7'b0100000) &&
                     ((funct3 == 3'b000) || (funct3 == 3'b101))) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.reg_write = 1'b1;
        end else if ((funct7 == 7'b0000001) &&
                     ((funct3 == 3'b000) || (funct3[2] == 1'b1))) begin
          // MULW (000), DIVW (100), DIVUW (101), REMW (110), REMUW (111);
          // there are no MULHW-class encodings.
          ctrl_o.valid = 1'b1;
          ctrl_o.reg_write = 1'b1;
          ctrl_o.muldiv = 1'b1;
        end else begin
          // W-form B ops in OP-32 space.
          ctrl_o.bext_op = 7'd63;
          if (funct7 == 7'b0000100 && funct3 == 3'b000)
            ctrl_o.bext_op = 7'd0;               // add.uw
          if (funct7 == 7'b0000100 && funct3 == 3'b100)
            ctrl_o.bext_op = 7'd40;              // packw (zext.h)
          if (funct7 == 7'b0010000 && funct3 == 3'b010)
            ctrl_o.bext_op = 7'd4;               // sh1add.uw
          if (funct7 == 7'b0010000 && funct3 == 3'b100)
            ctrl_o.bext_op = 7'd5;               // sh2add.uw
          if (funct7 == 7'b0010000 && funct3 == 3'b110)
            ctrl_o.bext_op = 7'd6;               // sh3add.uw
          if (funct7 == 7'b0110000 && funct3 == 3'b001)
            ctrl_o.bext_op = 7'd24;              // rolw
          if (funct7 == 7'b0110000 && funct3 == 3'b101)
            ctrl_o.bext_op = 7'd26;              // rorw
          if (ctrl_o.bext_op != 7'd63) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.reg_write = 1'b1;
            ctrl_o.bext = 1'b1;
          end
        end
      end
      7'b0001111: begin  // FENCE / FENCE.I: NOP in stage 1
        ctrl_o.valid = 1'b1;
      end
      7'b0101111: begin  // AMO / LR / SC (funct3: 010=.W, 011=.D)
        if ((funct3 == 3'b010) || (funct3 == 3'b011)) begin
          ctrl_o.amo_op = instr_i[31:27];
          ctrl_o.alu_src_imm = 1'b1;  // address = rs1 + 0
          imm_o = 64'd0;
          unique case (instr_i[31:27])
            5'b00010: begin  // LR (rs2 field must be x0)
              if (rs2_o == 5'd0) begin
                ctrl_o.valid = 1'b1;
                ctrl_o.reg_write = 1'b1;
                ctrl_o.mem_read = 1'b1;
                ctrl_o.lr = 1'b1;
              end
            end
            5'b00011: begin  // SC (mem_read set: result is MEM-stage)
              ctrl_o.valid = 1'b1;
              ctrl_o.reg_write = 1'b1;
              ctrl_o.mem_read = 1'b1;
              ctrl_o.mem_write = 1'b1;
              ctrl_o.sc = 1'b1;
            end
            5'b00000, 5'b00001, 5'b00100, 5'b01000, 5'b01100,
            5'b10000, 5'b10100, 5'b11000, 5'b11100: begin  // AMO*
              ctrl_o.valid = 1'b1;
              ctrl_o.reg_write = 1'b1;
              ctrl_o.mem_read = 1'b1;
              ctrl_o.mem_write = 1'b1;
              ctrl_o.amo = 1'b1;
            end
            default: ;
          endcase
        end
      end
      7'b0000111, 7'b0100111: begin
        // FLW/FLD, FSW/FSD, and vector loads/stores. Vector
        // forms (mew=0, width in funct3; index width for the
        // indexed classes): unit-stride, strided, indexed
        // (unordered/ordered), whole-register, and
        // fault-only-first loads. The class rides in bext_op
        // (VLS_*); the core snapshots the nf field for
        // segment/whole-register counts.
        logic is_store_v, vec_ls;
        logic [6:0] vclass;
        is_store_v = (opcode == 7'b0100111);
        if (is_store_v) imm_o = imm_s;
        vec_ls = 1'b0;
        vclass = VLS_UNIT;
        if ((funct3 == 3'b000 || funct3 == 3'b101 ||
             funct3 == 3'b110 || funct3 == 3'b111) &&
            !instr_i[28]) begin
          if (instr_i[27:26] == 2'b00) begin
            if (instr_i[24:20] == 5'd0) begin
              vec_ls = 1'b1;  // unit-stride (+ segments by nf)
              vclass = VLS_UNIT;
            end else if (instr_i[24:20] == 5'd8) begin
              vec_ls = (instr_i[31:29] == 3'd0) ||
                       (instr_i[31:29] == 3'd1) ||
                       (instr_i[31:29] == 3'd3) ||
                       (instr_i[31:29] == 3'd7);
              vclass = VLS_WHOLE;
            end else if (!is_store_v && (instr_i[24:20] == 5'd16)) begin
              vec_ls = 1'b1;  // fault-only-first (+ segments)
              vclass = VLS_FF;
            end else if ((instr_i[24:20] == 5'd11) &&
                         (funct3 == 3'b000)) begin
              vec_ls = instr_i[31:29] == 3'd0;  // vlm.v / vsm.v
              vclass = VLS_MASK;
            end
          end else begin
            vec_ls = 1'b1;  // strided/indexed (+ segments)
            vclass = (instr_i[27:26] == 2'b10) ? VLS_STRIDED
                                               : VLS_INDEXED;
          end
        end
        if (vec_ls) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.mem_read = !is_store_v;
          ctrl_o.mem_write = is_store_v;
          ctrl_o.alu_src_imm = 1'b1;
          ctrl_o.vec = 1'b1;
          ctrl_o.vec_rd = !is_store_v;
          ctrl_o.bext_op = vclass;
          imm_o = 64'd0;
        end else if (funct3 == 3'b010 || funct3 == 3'b011) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.mem_read = !is_store_v;
          ctrl_o.mem_write = is_store_v;
          ctrl_o.alu_src_imm = 1'b1;
          ctrl_o.fp = 1'b1;
          ctrl_o.fp_rd = !is_store_v;
          ctrl_o.fp_rs2 = is_store_v;
          ctrl_o.fmt_d = funct3[0];
          imm_o = is_store_v ? imm_s : imm_i;
        end
      end
      7'b1000011, 7'b1000111, 7'b1001011, 7'b1001111: begin  // FMA
        // rs3 = instr[31:27], fmt = instr[26:25], rm = funct3
        if (instr_i[26:25] <= 2'b01 &&
            (funct3 <= 3'b100 || funct3 == 3'b111)) begin
          ctrl_o.valid = 1'b1;
          ctrl_o.fp = 1'b1;
          ctrl_o.fp_op = 1'b1;
          ctrl_o.fp_rm = 1'b1;
          ctrl_o.fp_rd = 1'b1;
          ctrl_o.fp_rs1 = 1'b1;
          ctrl_o.fp_rs2 = 1'b1;
          ctrl_o.fmt_d = instr_i[25];
          unique case (instr_i[6:0])
            7'b1000011: ctrl_o.fpu_op = 5'd12;  // FMADD
            7'b1000111: ctrl_o.fpu_op = 5'd13;  // FMSUB
            7'b1001011: ctrl_o.fpu_op = 5'd14;  // FNMSUB
            default:    ctrl_o.fpu_op = 5'd15;  // FNMADD
          endcase
        end
      end
      7'b1010011: begin  // OP-FP: funct7 = {funct5, fmt[1:0]}
        if (instr_i[26:25] <= 2'b01) begin
          ctrl_o.fp = 1'b1;
          ctrl_o.fp_op = 1'b1;
          ctrl_o.fmt_d = instr_i[25];
          unique case (instr_i[31:27])
            5'b00000, 5'b00001, 5'b00010, 5'b00011: begin
              // FADD/FSUB/FMUL/FDIV
              if (funct3 <= 3'b100 || funct3 == 3'b111) begin
                ctrl_o.valid = 1'b1;
                ctrl_o.fp_rd = 1'b1;
                ctrl_o.fp_rs1 = 1'b1;
                ctrl_o.fp_rs2 = 1'b1;
                ctrl_o.fp_rm = 1'b1;
                ctrl_o.fpu_op = {3'b0, instr_i[28:27]};
              end
            end
            5'b01011: begin  // FSQRT (rs2 must be x0/f0 field 0)
              if ((instr_i[24:20] == 5'd0) &&
                  (funct3 <= 3'b100 || funct3 == 3'b111)) begin
                ctrl_o.valid = 1'b1;
                ctrl_o.fp_rd = 1'b1;
                ctrl_o.fp_rs1 = 1'b1;
                ctrl_o.fp_rm = 1'b1;
                ctrl_o.fpu_op = 5'd4;
              end
            end
            5'b00100: begin  // FSGNJ/N/X (funct3 selects)
              if (funct3 <= 3'b010) begin
                ctrl_o.valid = 1'b1;
                ctrl_o.fp_rd = 1'b1;
                ctrl_o.fp_rs1 = 1'b1;
                ctrl_o.fp_rs2 = 1'b1;
                ctrl_o.fpu_op = 5'd5;
                ctrl_o.fpu_aux = funct3[1:0];
              end
            end
            5'b00101: begin  // FMIN/FMAX
              if (funct3 <= 3'b001) begin
                ctrl_o.valid = 1'b1;
                ctrl_o.fp_rd = 1'b1;
                ctrl_o.fp_rs1 = 1'b1;
                ctrl_o.fp_rs2 = 1'b1;
                ctrl_o.fpu_op = 5'd6;
                ctrl_o.fpu_aux = {1'b0, funct3[0]};
              end
            end
            5'b01000: begin  // FCVT.fmt.fmt (rs2 = source fmt)
              if ((instr_i[24:20] <= 5'd1) &&
                  (instr_i[20] != instr_i[25]) &&
                  (funct3 <= 3'b100 || funct3 == 3'b111)) begin
                ctrl_o.valid = 1'b1;
                ctrl_o.fp_rd = 1'b1;
                ctrl_o.fp_rs1 = 1'b1;
                ctrl_o.fp_rm = 1'b1;
                ctrl_o.fpu_op = 5'd11;
              end
            end
            5'b11000: begin  // FCVT.W/WU/L/LU.fmt (rs2 = size)
              if ((instr_i[24:20] <= 5'd3) &&
                  (funct3 <= 3'b100 || funct3 == 3'b111)) begin
                ctrl_o.valid = 1'b1;
                ctrl_o.reg_write = 1'b1;
                ctrl_o.fp_rs1 = 1'b1;
                ctrl_o.fp_rm = 1'b1;
                ctrl_o.fpu_op = 5'd9;
                ctrl_o.fpu_aux = instr_i[21:20];
              end
            end
            5'b11010: begin  // FCVT.fmt.W/WU/L/LU
              if ((instr_i[24:20] <= 5'd3) &&
                  (funct3 <= 3'b100 || funct3 == 3'b111)) begin
                ctrl_o.valid = 1'b1;
                ctrl_o.fp_rd = 1'b1;
                ctrl_o.fp_rm = 1'b1;
                ctrl_o.fpu_op = 5'd10;
                ctrl_o.fpu_aux = instr_i[21:20];
              end
            end
            5'b11100: begin  // FMV.X.fmt / FCLASS (rs2 = 0)
              if (instr_i[24:20] == 5'd0 && funct3 <= 3'b001) begin
                ctrl_o.valid = 1'b1;
                ctrl_o.reg_write = 1'b1;
                ctrl_o.fp_rs1 = 1'b1;
                ctrl_o.fpu_op = funct3[0] ? 5'd8 : 5'd17;
              end
            end
            5'b11110: begin  // FMV.fmt.X (rs2 = 0, funct3 = 0)
              if (instr_i[24:20] == 5'd0 && funct3 == 3'b000) begin
                ctrl_o.valid = 1'b1;
                ctrl_o.fp_rd = 1'b1;
                ctrl_o.fpu_op = 5'd16;
              end
            end
            5'b10100: begin  // FEQ/FLT/FLE
              if (funct3 <= 3'b010) begin
                ctrl_o.valid = 1'b1;
                ctrl_o.reg_write = 1'b1;
                ctrl_o.fp_rs1 = 1'b1;
                ctrl_o.fp_rs2 = 1'b1;
                ctrl_o.fpu_op = 5'd7;
                ctrl_o.fpu_aux = funct3[1:0];
              end
            end
            default: ctrl_o.fp = 1'b0;
          endcase
          if (!ctrl_o.valid) begin
            ctrl_o.fp = 1'b0;
            ctrl_o.fp_op = 1'b0;
          end
        end
      end
      7'b1010111: begin  // OP-V (RVV 1.0 integer classes)
        // funct6 = instr[31:26], vm = instr[25]. Vector op is
        // carried in bext_op (VOP_*), operand form in fpu_aux
        // (VV for funct3 000/010, VX for 100/110, VI for 011).
        // Sub-operations for VOP_MLOG/VOP_RED/VOP_EXT/VOP_MSBIT
        // ride in the low immediate bits.
        imm_o = {{59{instr_i[19]}}, instr_i[19:15]};  // imm5
        if (funct3 == 3'b111) begin
          // vsetvli (bit31=0), vsetivli (31:30=11), vsetvl
          // (31:25=1000000). Form in fpu_aux: 0/1/2.
          if (!instr_i[31] || (instr_i[31:30] == 2'b11) ||
              (instr_i[31:25] == 7'b1000000)) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.vec = 1'b1;
            ctrl_o.vset = 1'b1;
            ctrl_o.reg_write = 1'b1;
            ctrl_o.fpu_aux = !instr_i[31] ? 2'd0 :
                             (instr_i[30] ? 2'd1 : 2'd2);
          end
        end else begin
          logic opm, ok, vf;
          logic [6:0] vop;
          opm = (funct3 == 3'b010) || (funct3 == 3'b110);
          vf = (funct3 == 3'b101);
          ctrl_o.fpu_aux = ((funct3 == 3'b000) ||
                            (funct3 == 3'b010)) ? VFORM_VV :
                           ((funct3 == 3'b100) ||
                            (funct3 == 3'b110)) ? VFORM_VX : VFORM_VI;
          vop = 7'd127;
          ok = 1'b1;
          if ((funct3 == 3'b001) || (funct3 == 3'b101)) begin
            // OPFVV / OPFVF: floating-point vector (stage 9).
            // The scalar FPU op rides in imm[4:0] (ADD=0,
            // SUB=1, MUL=2, DIV=3, SGNJ=5, MINMAX=6), aux
            // in imm[6:5], operand-swap/wide-vs2/madd-form
            // in imm[7].
            ctrl_o.fpu_aux = vf ? VFORM_VX : VFORM_VV;
            imm_o = 64'd0;
            unique case (instr_i[31:26])
              6'd0: begin vop = VOP_FBIN; imm_o[4:0] = 5'd0; end
              6'd2: begin vop = VOP_FBIN; imm_o[4:0] = 5'd1; end
              6'd39: begin  // vfrsub.vf
                vop = VOP_FBIN; imm_o[4:0] = 5'd1; imm_o[7] = 1'b1;
                ok = vf;
              end
              6'd4: begin vop = VOP_FBIN; imm_o[4:0] = 5'd6; end
              6'd6: begin
                vop = VOP_FBIN; imm_o[4:0] = 5'd6; imm_o[5] = 1'b1;
              end
              6'd8, 6'd9, 6'd10: begin
                vop = VOP_FBIN; imm_o[4:0] = 5'd5;
                imm_o[6:5] = instr_i[27:26];  // sgnj/n/x aux
              end
              6'd32: begin vop = VOP_FBIN; imm_o[4:0] = 5'd3; end
              6'd33: begin  // vfrdiv.vf
                vop = VOP_FBIN; imm_o[4:0] = 5'd3; imm_o[7] = 1'b1;
                ok = vf;
              end
              6'd36: begin vop = VOP_FBIN; imm_o[4:0] = 5'd2; end
              6'd40, 6'd41, 6'd42, 6'd43: begin  // vfmadd family
                vop = VOP_FMACC; imm_o[7] = 1'b1;
                imm_o[6:5] = instr_i[27:26];
              end
              6'd44, 6'd45, 6'd46, 6'd47: begin  // vfmacc family
                vop = VOP_FMACC; imm_o[6:5] = instr_i[27:26];
              end
              6'd48: begin vop = VOP_FBINW; imm_o[4:0] = 5'd0; end
              6'd50: begin vop = VOP_FBINW; imm_o[4:0] = 5'd1; end
              6'd52: begin
                vop = VOP_FBINW; imm_o[4:0] = 5'd0; imm_o[7] = 1'b1;
              end
              6'd54: begin
                vop = VOP_FBINW; imm_o[4:0] = 5'd1; imm_o[7] = 1'b1;
              end
              6'd56: begin vop = VOP_FBINW; imm_o[4:0] = 5'd2; end
              6'd60, 6'd61, 6'd62, 6'd63: begin  // vfwmacc family
                vop = VOP_FMACCW; imm_o[6:5] = instr_i[27:26];
              end
              6'd24: begin vop = VOP_FCMP; imm_o[2:0] = 3'd0; end
              6'd28: begin vop = VOP_FCMP; imm_o[2:0] = 3'd1; end
              6'd27: begin vop = VOP_FCMP; imm_o[2:0] = 3'd2; end
              6'd25: begin vop = VOP_FCMP; imm_o[2:0] = 3'd3; end
              6'd29: begin
                vop = VOP_FCMP; imm_o[2:0] = 3'd4; ok = vf;
              end
              6'd31: begin
                vop = VOP_FCMP; imm_o[2:0] = 3'd5; ok = vf;
              end
              6'd18: begin  // vfcvt / vfwcvt / vfncvt (.vv only)
                vop = VOP_FCVT;
                imm_o[4:0] = instr_i[19:15];
                ok = !vf && (instr_i[19:15] < 5'd24) &&
                     ((instr_i[17:15] != 3'd5) ||
                      (instr_i[19:15] == 5'd21)) &&
                     ((instr_i[17:15] != 3'd4) ||
                      (instr_i[19:15] >= 5'd8));
              end
              6'd19: begin  // vfsqrt / vfrec7 / vfrsqrt7 / vfclass
                vop = VOP_FUNARY;
                ok = !vf && ((instr_i[19:15] == 5'd0) ||
                             (instr_i[19:15] == 5'd4) ||
                             (instr_i[19:15] == 5'd5) ||
                             (instr_i[19:15] == 5'd16));
                imm_o[1:0] = (instr_i[19:15] == 5'd16) ? 2'd1 :
                             (instr_i[19:15] == 5'd4)  ? 2'd2 :
                             (instr_i[19:15] == 5'd5)  ? 2'd3 : 2'd0;
              end
              6'd1, 6'd3, 6'd5, 6'd7: begin  // vfred* (.vs only)
                vop = VOP_FRED;
                imm_o[1:0] = instr_i[28:27];  // usu/osu/min/max
                ok = !vf;
              end
              6'd49, 6'd51: begin  // vfwredusum/osum
                vop = VOP_FWRED;
                imm_o[1:0] = {1'b0, instr_i[27]};
                ok = !vf;
              end
              6'd23: begin  // vfmerge.vfm / vfmv.v.f
                ok = vf;
                if (!instr_i[25]) vop = VOP_MERGE;
                else begin
                  vop = VOP_MV;
                  ok = vf && (instr_i[24:20] == 5'd0);
                end
              end
              6'd16: begin  // vfmv.s.f / vfmv.f.s
                if (vf) begin
                  vop = VOP_MVSX;
                  ok = instr_i[24:20] == 5'd0;
                end else begin
                  vop = VOP_FMVFS;
                  ok = instr_i[19:15] == 5'd0;
                end
              end
              6'd14: begin vop = VOP_SLIDE1UP; ok = vf; end
              6'd15: begin vop = VOP_SLIDE1DOWN; ok = vf; end
              default: ok = 1'b0;
            endcase
          end else if (!opm) begin
            // OPIVV / OPIVX / OPIVI
            unique case (instr_i[31:26])
              6'd0: vop = VOP_ADD;
              6'd2: vop = VOP_SUB;
              6'd3: begin
                vop = VOP_RSUB;
                ok = funct3 != 3'b000;  // no vrsub.vv
              end
              6'd4: vop = VOP_MINU;
              6'd5: vop = VOP_MIN;
              6'd6: vop = VOP_MAXU;
              6'd7: vop = VOP_MAX;
              6'd9: vop = VOP_AND;
              6'd10: vop = VOP_OR;
              6'd11: vop = VOP_XOR;
              6'd12: vop = VOP_GATHER;
              6'd14: vop = (funct3 == 3'b000) ? VOP_GATHEREI16
                                              : VOP_SLIDEUP;
              6'd15: begin
                vop = VOP_SLIDEDOWN;
                ok = funct3 != 3'b000;  // no vslidedown.vv
              end
              6'd16: begin
                vop = VOP_ADC;
                ok = !instr_i[25];      // carry-in form needs vm=0
              end
              6'd17: vop = VOP_MADC;
              6'd18: begin
                vop = VOP_SBC;
                ok = !instr_i[25];
              end
              6'd19: vop = VOP_MSBC;
              6'd23: begin
                if (!instr_i[25]) vop = VOP_MERGE;
                else begin
                  vop = VOP_MV;         // vmv.v.* (vmerge, vm=1)
                  ok = instr_i[24:20] == 5'd0;
                end
              end
              6'd24: vop = VOP_CMPEQ;
              6'd25: vop = VOP_CMPNE;
              6'd26: vop = VOP_CMPLTU;
              6'd27: begin
                vop = VOP_CMPLT;
                ok = funct3 != 3'b011;  // vmslt.vi is a pseudo-op
              end
              6'd28: vop = VOP_CMPLEU;
              6'd29: vop = VOP_CMPLE;
              6'd30: begin
                vop = VOP_CMPGTU;
                ok = funct3 != 3'b000;  // no vmsgtu.vv
              end
              6'd31: begin
                vop = VOP_CMPGT;
                ok = funct3 != 3'b000;  // no vmsgt.vv
              end
              6'd32: vop = VOP_SADDU;
              6'd33: vop = VOP_SADD;
              6'd34: begin
                vop = VOP_SSUBU;
                ok = funct3 != 3'b011;  // no vssubu.vi
              end
              6'd35: begin
                vop = VOP_SSUB;
                ok = funct3 != 3'b011;  // no vssub.vi
              end
              6'd37: vop = VOP_SLL;
              6'd39: begin
                if (funct3 == 3'b011) begin
                  vop = VOP_MVR;        // vmv<nr>r.v
                  ok = (instr_i[19:15] == 5'd0) ||
                       (instr_i[19:15] == 5'd1) ||
                       (instr_i[19:15] == 5'd3) ||
                       (instr_i[19:15] == 5'd7);
                end else begin
                  vop = VOP_SMUL;
                end
              end
              6'd40: vop = VOP_SRL;
              6'd41: vop = VOP_SRA;
              6'd42: vop = VOP_SSRL;
              6'd43: vop = VOP_SSRA;
              6'd48: begin
                vop = VOP_WRED;         // vwredsumu.vs
                ok = funct3 == 3'b000;
                imm_o = 64'd0;
              end
              6'd49: begin
                vop = VOP_WRED;         // vwredsum.vs
                ok = funct3 == 3'b000;
                imm_o = 64'd1;
              end
              6'd44: vop = VOP_NSRL;
              6'd45: vop = VOP_NSRA;
              6'd46: vop = VOP_NCLIPU;
              6'd47: vop = VOP_NCLIP;
              default: ok = 1'b0;
            endcase
          end else begin
            // OPMVV / OPMVX
            unique case (instr_i[31:26])
              6'd0, 6'd1, 6'd2, 6'd3,
              6'd4, 6'd5, 6'd6, 6'd7: begin
                vop = VOP_RED;
                ok = funct3 == 3'b010;
                imm_o = {61'd0, instr_i[28:26]};
              end
              6'd8: vop = VOP_AADDU;
              6'd9: vop = VOP_AADD;
              6'd10: vop = VOP_ASUBU;
              6'd11: vop = VOP_ASUB;
              6'd14: begin
                vop = VOP_SLIDE1UP;
                ok = funct3 == 3'b110;
              end
              6'd15: begin
                vop = VOP_SLIDE1DOWN;
                ok = funct3 == 3'b110;
              end
              6'd16: begin
                if (funct3 == 3'b110) begin
                  vop = VOP_MVSX;       // vmv.s.x
                  ok = instr_i[24:20] == 5'd0;
                end else if (instr_i[19:15] == 5'd0) begin
                  vop = VOP_MVXS;       // vmv.x.s
                end else if (instr_i[19:15] == 5'd16) begin
                  vop = VOP_CPOP;
                end else if (instr_i[19:15] == 5'd17) begin
                  vop = VOP_FIRST;
                end else begin
                  ok = 1'b0;
                end
              end
              6'd18: begin
                vop = VOP_EXT;          // vzext/vsext.vf2/4/8
                ok = (funct3 == 3'b010) &&
                     (instr_i[19:18] == 2'b00) &&
                     (instr_i[17:15] >= 3'd2);
                imm_o = {61'd0, instr_i[17:15]};
              end
              6'd20: begin
                ok = funct3 == 3'b010;
                if (instr_i[19:15] == 5'd16) begin
                  vop = VOP_IOTA;
                end else if ((instr_i[19:15] == 5'd17) &&
                             (instr_i[24:20] == 5'd0)) begin
                  vop = VOP_ID;
                end else if ((instr_i[19:15] >= 5'd1) &&
                             (instr_i[19:15] <= 5'd3)) begin
                  vop = VOP_MSBIT;      // vmsbf/vmsof/vmsif
                  imm_o = {62'd0, instr_i[16:15]};
                end else begin
                  ok = 1'b0;
                end
              end
              6'd23: begin
                vop = VOP_COMPRESS;
                ok = (funct3 == 3'b010) && instr_i[25];
              end
              6'd24, 6'd25, 6'd26, 6'd27,
              6'd28, 6'd29, 6'd30, 6'd31: begin
                vop = VOP_MLOG;         // mask logicals (unmasked)
                ok = (funct3 == 3'b010) && instr_i[25];
                imm_o = {61'd0, instr_i[28:26]};
              end
              6'd32: vop = VOP_DIVU;
              6'd33: vop = VOP_DIV;
              6'd34: vop = VOP_REMU;
              6'd35: vop = VOP_REM;
              6'd36: vop = VOP_MULHU;
              6'd37: vop = VOP_MUL;
              6'd38: vop = VOP_MULHSU;
              6'd39: vop = VOP_MULH;
              6'd41: vop = VOP_MADD;
              6'd43: vop = VOP_NMSUB;
              6'd45: vop = VOP_MACC;
              6'd47: vop = VOP_NMSAC;
              6'd48: vop = VOP_WADDU;
              6'd49: vop = VOP_WADD;
              6'd50: vop = VOP_WSUBU;
              6'd51: vop = VOP_WSUB;
              6'd52: vop = VOP_WADDUW;
              6'd53: vop = VOP_WADDW;
              6'd54: vop = VOP_WSUBUW;
              6'd55: vop = VOP_WSUBW;
              6'd56: vop = VOP_WMULU;
              6'd58: vop = VOP_WMULSU;
              6'd59: vop = VOP_WMUL;
              6'd60: vop = VOP_WMACCU;
              6'd61: vop = VOP_WMACC;
              6'd62: begin
                vop = VOP_WMACCUS;
                ok = funct3 == 3'b110;  // .vx only
              end
              6'd63: vop = VOP_WMACCSU;
              default: ok = 1'b0;
            endcase
          end
          if (ok && (vop != 7'd127)) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.vec = 1'b1;
            ctrl_o.bext_op = vop;
            if (vf) ctrl_o.fp_rs1 = 1'b1;
            if ((vop == VOP_MVXS) || (vop == VOP_CPOP) ||
                (vop == VOP_FIRST)) begin
              ctrl_o.reg_write = 1'b1;
            end else if (vop == VOP_FMVFS) begin
              ctrl_o.fp_rd = 1'b1;  // vfmv.f.s writes an FP reg
            end else begin
              ctrl_o.vec_rd = 1'b1;
            end
          end
        end
      end
      7'b1110011: begin  // SYSTEM
        if (funct3 == 3'b000) begin
          if (instr_i[31:20] == 12'd0) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.ecall = 1'b1;
          end else if (instr_i[31:20] == 12'd1) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.ebreak = 1'b1;
          end else if (instr_i[31:20] == 12'h302) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.mret = 1'b1;
          end else if (instr_i[31:20] == 12'h102) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.sret = 1'b1;
          end else if (instr_i[31:20] == 12'h105) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.wfi = 1'b1;
          end else if (funct7 == 7'b0001001) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.sfence = 1'b1;
          end else if (funct7 == 7'b0010001) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.hfence = 1'b1;           // HFENCE.VVMA
          end else if (funct7 == 7'b0110001) begin
            ctrl_o.valid = 1'b1;
            ctrl_o.hfence = 1'b1;           // HFENCE.GVMA
            ctrl_o.hfence_gvma = 1'b1;
          end
        end else if (funct3 == 3'b100) begin
          // HLV/HLVX/HSV: funct7[6:3]=0110, size in [27:26],
          // store in [25]. Loads select signed/unsigned/HLVX
          // in instr[24:20] (0/1/3); address is rs1 with no
          // offset. ctrl funct3 is rewritten to the ordinary
          // load/store size+sign encoding for the MEM stage.
          if (instr_i[31:28] == 4'b0110) begin
            if (!instr_i[25]) begin
              if ((instr_i[24:20] == 5'd0) ||
                  ((instr_i[24:20] == 5'd1) &&
                   (instr_i[27:26] != 2'b11)) ||
                  ((instr_i[24:20] == 5'd3) &&
                   ((instr_i[27:26] == 2'b01) ||
                    (instr_i[27:26] == 2'b10)))) begin
                ctrl_o.valid = 1'b1;
                ctrl_o.reg_write = 1'b1;
                ctrl_o.mem_read = 1'b1;
                ctrl_o.hlv = 1'b1;
                ctrl_o.hlvx = (instr_i[24:20] == 5'd3);
                ctrl_o.alu_src_imm = 1'b1;
                imm_o = 64'd0;
                unique case (instr_i[27:26])
                  2'b00: ctrl_o.funct3 = instr_i[20] ? 3'b100 : 3'b000;
                  2'b01: ctrl_o.funct3 = instr_i[20] ? 3'b101 : 3'b001;
                  2'b10: ctrl_o.funct3 = instr_i[20] ? 3'b110 : 3'b010;
                  default: ctrl_o.funct3 = 3'b011;
                endcase
              end
            end else if (instr_i[11:7] == 5'd0) begin
              ctrl_o.valid = 1'b1;
              ctrl_o.mem_write = 1'b1;
              ctrl_o.hlv = 1'b1;
              ctrl_o.alu_src_imm = 1'b1;
              imm_o = 64'd0;
              ctrl_o.funct3 = {1'b0, instr_i[27:26]};
            end
          end
        end else begin
          // CSRRW/CSRRS/CSRRC and immediate forms. CSR existence
          // and privilege are checked in EX by the CSR file.
          ctrl_o.valid = 1'b1;
          ctrl_o.reg_write = 1'b1;
          ctrl_o.csr = 1'b1;
          ctrl_o.csr_imm = funct3[2];
          imm_o = imm_i;
        end
      end
      default: begin
        ctrl_o = '0;
        ctrl_o.funct3 = funct3;
      end
    endcase

    // Without the vector unit (sigil_pkg::HAS_VECTOR = 0) every
    // vector encoding is reserved: OP-V (vset{i}vl{i} included)
    // and the vector loads/stores in the LOAD-FP/STORE-FP space
    // (widths 000/101/110/111) raise illegal-instruction, as on a
    // core without V. Scalar FP loads/stores are unaffected.
    if (!HAS_VECTOR && ctrl_o.vec) ctrl_o.valid = 1'b0;

    // Contract: an illegal encoding asserts no side-effecting
    // control at all, regardless of which guard rejected it. The
    // core also gates writes on the trap, but the decoder output
    // alone must be safe to consume (stage 2 registers it).
    if (!ctrl_o.valid) begin
      ctrl_o = '0;
      ctrl_o.funct3 = funct3;
    end
  end
endmodule
`default_nettype wire
