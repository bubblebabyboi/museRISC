// Shared types for the in-house RV64 core (issue #18, stage 1).
`default_nettype none
package sigil_pkg;

  // Package constants are consumed selectively per module (e.g. the
  // ALU needs none of the trap causes), so unused-parameter lint is
  // off for the whole package.
  /* verilator lint_off UNUSEDPARAM */
  localparam int unsigned XLEN = 64;

  // ALU operations. Word (W-variant) behavior is selected separately.
  typedef enum logic [3:0] {
    ALU_ADD,
    ALU_SUB,
    ALU_SLL,
    ALU_SLT,
    ALU_SLTU,
    ALU_XOR,
    ALU_SRL,
    ALU_SRA,
    ALU_OR,
    ALU_AND,
    ALU_COPY_B  // result = operand B (LUI)
  } alu_op_e;

  // Decoder output consumed by the datapath. One struct so stage 2
  // can register it verbatim between decode and execute.
  typedef struct packed {
    logic    vec;          // any vector instruction (incl. vset)
    logic    vec_rd;       // destination is a vector register group
    logic    vset;         // vsetvli/vsetivli/vsetvl (form in fpu_aux)
    logic [6:0] bext_op;   // B/crypto op; vector op (VOP_*) if vec
    logic    bext;         // result comes from the B/crypto unit
    logic [4:0] fpu_op;    // FPU operation (sigil_fpu FPU_*)
    logic [1:0] fpu_aux;   // sgnj/min-max/cmp, cvt size; vec form if vec
    logic    fmt_d;        // FP format: 1=binary64, 0=binary32
    logic    fp_op;        // result comes from the FPU in EX
    logic    fp_rm;        // op consumes a rounding mode
    logic    fp_rd;        // destination is an FP register
    logic    fp_rs1;       // rs1 read from the FP regfile
    logic    fp_rs2;       // rs2 read from the FP regfile
    logic    fp;           // any FP instruction (FS must be > 0)
    logic [4:0] amo_op;    // AMO funct5 (instr[31:27])
    logic    sc;           // store-conditional (result = success flag)
    logic    lr;           // load-reserved (sets the reservation)
    logic    amo;          // atomic RMW (funct5 in amo_op)
    logic    hlv;          // HLV/HLVX/HSV guest-memory access
    logic    hlvx;         // HLVX (execute-permission load)
    logic    hfence;       // HFENCE.VVMA/GVMA (full TLB flush here)
    logic    hfence_gvma;  // GVMA variant (TVM legality differs)
    logic    sfence;       // SFENCE.VMA (serializing; flushes TLBs)
    logic    wfi;          // WFI (executes as NOP unless TW traps it)
    logic    sret;         // SRET
    logic    mret;         // MRET
    logic    csr_imm;      // CSR source is the 5-bit zero-extended rs1 field
    logic    csr;          // CSR read/write instruction (funct3 selects op)
    logic    muldiv;       // result comes from the M unit (funct3 selects)
    logic    valid;        // legal instruction in the implemented subset
    logic    reg_write;    // write rd at end of cycle
    logic    mem_read;     // load: rd takes loaded data
    logic    mem_write;    // store: byte enables from funct3
    logic    alu_src_imm;  // ALU operand B is the immediate
    logic    alu_a_pc;     // ALU operand A is the PC (AUIPC)
    logic    word_op;      // 32-bit W-variant semantics in the ALU
    alu_op_e alu_op;
    logic    branch;       // conditional branch, condition in funct3
    logic    jal;
    logic    jalr;
    logic    ecall;
    logic    ebreak;
    logic [2:0] funct3;    // branch condition / load-store size+sign
  } ctrl_t;

  // mcause values the stage-1 core can raise.
  localparam logic [63:0] CAUSE_ILLEGAL_INSTR = 64'd2;
  localparam logic [63:0] CAUSE_BREAKPOINT    = 64'd3;
  localparam logic [63:0] CAUSE_LOAD_MISALIGN = 64'd4;
  localparam logic [63:0] CAUSE_STORE_MISALIGN = 64'd6;
  localparam logic [63:0] CAUSE_ECALL_M       = 64'd11;

  // Vector unit operations (stage 8, carried in bext_op) and
  // operand forms (carried in fpu_aux). VLEN/ELEN are fixed
  // for the in-house core's first vector configuration.
  localparam int unsigned VLEN = 512;
  localparam int unsigned ELEN = 64;
  localparam logic [6:0] VOP_ADD  = 7'd0;
  localparam logic [6:0] VOP_SUB  = 7'd1;
  localparam logic [6:0] VOP_RSUB = 7'd2;
  localparam logic [6:0] VOP_AND  = 7'd3;
  localparam logic [6:0] VOP_OR   = 7'd4;
  localparam logic [6:0] VOP_XOR  = 7'd5;
  localparam logic [6:0] VOP_SLL  = 7'd6;
  localparam logic [6:0] VOP_SRL  = 7'd7;
  localparam logic [6:0] VOP_SRA  = 7'd8;
  localparam logic [6:0] VOP_MV   = 7'd9;   // vmv.v.v/.x/.i
  localparam logic [6:0] VOP_MVSX = 7'd10;  // vmv.s.x
  localparam logic [6:0] VOP_MVXS = 7'd11;  // vmv.x.s
  // Stage 8c additions. Sub-operation for VOP_MLOG/VOP_RED/
  // VOP_EXT/VOP_MSBIT rides in the low bits of the immediate.
  localparam logic [6:0] VOP_MIN   = 7'd12;
  localparam logic [6:0] VOP_MINU  = 7'd13;
  localparam logic [6:0] VOP_MAX   = 7'd14;
  localparam logic [6:0] VOP_MAXU  = 7'd15;
  localparam logic [6:0] VOP_MUL   = 7'd16;
  localparam logic [6:0] VOP_MULH  = 7'd17;
  localparam logic [6:0] VOP_MULHU = 7'd18;
  localparam logic [6:0] VOP_MULHSU= 7'd19;
  localparam logic [6:0] VOP_MACC  = 7'd20;  // vd += a*b
  localparam logic [6:0] VOP_MADD  = 7'd21;  // vd = b*vd + a
  localparam logic [6:0] VOP_NMSAC = 7'd22;  // vd -= a*b
  localparam logic [6:0] VOP_NMSUB = 7'd23;  // vd = a - b*vd
  localparam logic [6:0] VOP_DIV   = 7'd24;
  localparam logic [6:0] VOP_DIVU  = 7'd25;
  localparam logic [6:0] VOP_REM   = 7'd26;
  localparam logic [6:0] VOP_REMU  = 7'd27;
  localparam logic [6:0] VOP_ADC   = 7'd28;
  localparam logic [6:0] VOP_MADC  = 7'd29;  // mask dest: carry-out
  localparam logic [6:0] VOP_SBC   = 7'd30;
  localparam logic [6:0] VOP_MSBC  = 7'd31;  // mask dest: borrow-out
  localparam logic [6:0] VOP_MERGE = 7'd32;
  localparam logic [6:0] VOP_CMPEQ = 7'd33;  // mask dest compares
  localparam logic [6:0] VOP_CMPNE = 7'd34;
  localparam logic [6:0] VOP_CMPLTU= 7'd35;
  localparam logic [6:0] VOP_CMPLT = 7'd36;
  localparam logic [6:0] VOP_CMPLEU= 7'd37;
  localparam logic [6:0] VOP_CMPLE = 7'd38;
  localparam logic [6:0] VOP_CMPGTU= 7'd39;
  localparam logic [6:0] VOP_CMPGT = 7'd40;
  localparam logic [6:0] VOP_MLOG  = 7'd41;  // mask logical, imm=sub
  localparam logic [6:0] VOP_RED   = 7'd42;  // reduction, imm=sub
  localparam logic [6:0] VOP_EXT   = 7'd43;  // vzext/vsext, imm=sub
  localparam logic [6:0] VOP_SADD  = 7'd44;
  localparam logic [6:0] VOP_SADDU = 7'd45;
  localparam logic [6:0] VOP_SSUB  = 7'd46;
  localparam logic [6:0] VOP_SSUBU = 7'd47;
  localparam logic [6:0] VOP_AADD  = 7'd48;
  localparam logic [6:0] VOP_AADDU = 7'd49;
  localparam logic [6:0] VOP_ASUB  = 7'd50;
  localparam logic [6:0] VOP_ASUBU = 7'd51;
  localparam logic [6:0] VOP_SMUL  = 7'd52;
  localparam logic [6:0] VOP_SSRL  = 7'd53;
  localparam logic [6:0] VOP_SSRA  = 7'd54;
  localparam logic [6:0] VOP_WADD  = 7'd55;  // widening, narrow srcs
  localparam logic [6:0] VOP_WADDW = 7'd56;  // widening, wide vs2
  localparam logic [6:0] VOP_WADDU = 7'd57;
  localparam logic [6:0] VOP_WADDUW= 7'd58;
  localparam logic [6:0] VOP_WSUB  = 7'd59;
  localparam logic [6:0] VOP_WSUBW = 7'd60;
  localparam logic [6:0] VOP_WSUBU = 7'd61;
  localparam logic [6:0] VOP_WSUBUW= 7'd62;
  localparam logic [6:0] VOP_WMUL  = 7'd63;
  localparam logic [6:0] VOP_WMULU = 7'd64;
  localparam logic [6:0] VOP_WMULSU= 7'd65;
  localparam logic [6:0] VOP_WMACC = 7'd66;
  localparam logic [6:0] VOP_WMACCU= 7'd67;
  localparam logic [6:0] VOP_WMACCSU=7'd68;
  localparam logic [6:0] VOP_WMACCUS=7'd69;
  localparam logic [6:0] VOP_NSRL  = 7'd70;  // narrowing shifts/clips
  localparam logic [6:0] VOP_NSRA  = 7'd71;
  localparam logic [6:0] VOP_NCLIP = 7'd72;
  localparam logic [6:0] VOP_NCLIPU= 7'd73;
  localparam logic [6:0] VOP_SLIDEUP  = 7'd74;
  localparam logic [6:0] VOP_SLIDEDOWN= 7'd75;
  localparam logic [6:0] VOP_SLIDE1UP = 7'd76;
  localparam logic [6:0] VOP_SLIDE1DOWN=7'd77;
  localparam logic [6:0] VOP_GATHER   = 7'd78;
  localparam logic [6:0] VOP_GATHEREI16=7'd79;
  localparam logic [6:0] VOP_COMPRESS = 7'd80;
  localparam logic [6:0] VOP_MSBIT = 7'd81;  // vmsbf/vmsof/vmsif
  localparam logic [6:0] VOP_IOTA  = 7'd82;
  localparam logic [6:0] VOP_ID    = 7'd83;
  localparam logic [6:0] VOP_CPOP  = 7'd84;  // scalar result
  localparam logic [6:0] VOP_FIRST = 7'd85;  // scalar result
  localparam logic [6:0] VOP_MVR   = 7'd86;  // vmv<nr>r.v
  localparam logic [6:0] VOP_WRED  = 7'd87;  // vwredsum(u), imm[0]=sgn
  // FP vector classes (stage 9): the scalar FPU operation
  // rides in imm[4:0] (FPU_*), its aux in imm[6:5];
  // imm[7] swaps operands (vfrsub/vfrdiv), selects the
  // wide vs2 of vfwadd.w, or the madd FMA form.
  localparam logic [6:0] VOP_FBIN   = 7'd88;  // vfadd/sub/mul/..
  localparam logic [6:0] VOP_FBINW  = 7'd89;  // vfwadd/sub/mul(.w)
  localparam logic [6:0] VOP_FMACC  = 7'd90;  // vfma family
  localparam logic [6:0] VOP_FMACCW = 7'd91;  // vfwmacc family
  localparam logic [6:0] VOP_FCMP   = 7'd92;  // vmfeq.., imm[2:0]
  localparam logic [6:0] VOP_FUNARY = 7'd93;  // imm[1:0]: sqrt/class
  localparam logic [6:0] VOP_FCVT   = 7'd94;  // imm[4:0] = vs1 sub-op
  localparam logic [6:0] VOP_FRED   = 7'd95;  // imm[1:0]: usu/osu/min/max
  localparam logic [6:0] VOP_FWRED  = 7'd96;  // vfwredusum/osum
  localparam logic [6:0] VOP_FMVFS  = 7'd97;  // vfmv.f.s
  // Vector load/store classes (bext_op on vec mem ops).
  localparam logic [6:0] VLS_UNIT  = 7'd100;
  localparam logic [6:0] VLS_STRIDED = 7'd101;
  localparam logic [6:0] VLS_INDEXED = 7'd102;
  localparam logic [6:0] VLS_WHOLE = 7'd103;  // vl<nr>r / vs<nr>r
  localparam logic [6:0] VLS_FF    = 7'd104;  // fault-only-first
  localparam logic [6:0] VLS_MASK  = 7'd105;  // vlm.v / vsm.v
  localparam logic [1:0] VFORM_VV = 2'd0;
  localparam logic [1:0] VFORM_VX = 2'd1;
  localparam logic [1:0] VFORM_VI = 2'd2;
  /* verilator lint_on UNUSEDPARAM */

endpackage
`default_nettype wire
