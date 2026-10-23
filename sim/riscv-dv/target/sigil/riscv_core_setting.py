"""riscv-dv (pygen) core setting for the Sigil core (issue #8).

scripts/riscv_dv_setup.sh copies this file to
<build>/pygen/pygen_src/target/sigil/riscv_core_setting.py; pass
--target=sigil to the pygen tests. Structure follows the upstream
pygen targets (pygen/pygen_src/target/rv64imafdc).

What Sigil implements vs. what this file enables (pygen limits; the
full list with reasons is in docs/VERIFICATION.md):
- RV64IMAFDC + Zca/Zcd: enabled (RV32/RV64 I, M, A, F, D, C, DC groups).
- Zba/Zbb/Zbc/Zbs, Zbkb/Zbkc/Zbkx: pygen only has the draft-0.92 B
  extension as one RV32B group (no RV64 W forms, no Zba). The draft
  instructions that survived ratification with the same encoding
  are enabled (the setup patch renames pcnt/sbset/... to the ratified
  cpop/bset/... spellings); the dropped draft instructions are in
  unsupported_instr below.
- Zicond, Zkn (Zkne/Zknd/Zknh), Zcb, V (Zve64d, VLEN 512), H: not
  generated (pygen has no instruction classes for them).
- M/S/U: all three boot modes are used.
- Sv39: Sigil translates, but pygen cannot build page tables
  (create_page_table is a TODO upstream), so SATP_MODE is BARE here.
- PMP: Sigil has 16 entries, G=0. pygen's PMP setup is a TODO; the
  Sigil user_init.s opens entry 0 (NAPOT, RWX, whole PA space) so S/U
  code can run at all.
- Misaligned loads/stores trap on Sigil (and in the Spike config).
"""

import math
from pygen_src.riscv_instr_pkg import (privileged_reg_t, satp_mode_t,
                                       riscv_instr_group_t, mtvec_mode_t,
                                       privileged_mode_t, riscv_instr_name_t)

# -----------------------------------------------------------------------------
# Processor feature configuration
# -----------------------------------------------------------------------------

XLEN = 64

# Sigil: Sv39 (+Svnapot). Generator: no page tables in pygen -> Bare.
SATP_MODE = satp_mode_t.BARE

supported_privileged_mode = [privileged_mode_t.USER_MODE,
                             privileged_mode_t.SUPERVISOR_MODE,
                             privileged_mode_t.MACHINE_MODE]

# Draft-0.92 B instructions that are not part of ratified
# Zba/Zbb/Zbc/Zbs/Zbkb (or whose ratified form is a single immediate
# of a draft instruction, e.g. orc.b = gorci 7, rev8 = grevi 56):
# Sigil decodes them as illegal and GCC does not assemble them.
unsupported_instr = [
    riscv_instr_name_t.SLO, riscv_instr_name_t.SLOI,
    riscv_instr_name_t.SRO, riscv_instr_name_t.SROI,
    riscv_instr_name_t.GORC, riscv_instr_name_t.GORCI,
    riscv_instr_name_t.GREV, riscv_instr_name_t.GREVI,
    riscv_instr_name_t.SHFL, riscv_instr_name_t.SHFLI,
    riscv_instr_name_t.UNSHFL, riscv_instr_name_t.UNSHFLI,
    riscv_instr_name_t.BDEP, riscv_instr_name_t.BFP,
    riscv_instr_name_t.CMIX, riscv_instr_name_t.CMOV,
    riscv_instr_name_t.FSL, riscv_instr_name_t.FSR, riscv_instr_name_t.FSRI,
    riscv_instr_name_t.CRC32_B, riscv_instr_name_t.CRC32_H,
    riscv_instr_name_t.CRC32_W, riscv_instr_name_t.CRC32C_B,
    riscv_instr_name_t.CRC32C_H, riscv_instr_name_t.CRC32C_W,
    riscv_instr_name_t.PACKU,
]

supported_isa = [riscv_instr_group_t.RV32I, riscv_instr_group_t.RV64I,
                 riscv_instr_group_t.RV32M, riscv_instr_group_t.RV64M,
                 riscv_instr_group_t.RV32C, riscv_instr_group_t.RV64C,
                 riscv_instr_group_t.RV32A, riscv_instr_group_t.RV64A,
                 riscv_instr_group_t.RV32F, riscv_instr_group_t.RV64F,
                 riscv_instr_group_t.RV32D, riscv_instr_group_t.RV64D,
                 riscv_instr_group_t.RV32DC,
                 riscv_instr_group_t.RV32B]

# Sigil supports direct and vectored mtvec/stvec.
supported_interrupt_mode = [mtvec_mode_t.DIRECT, mtvec_mode_t.VECTORED]
max_interrupt_vector_num = 16

# pygen's PMP configuration is unimplemented upstream (setup_pmp and
# gen_pmp_csr_write are TODOs); keep it off. See user_init.s.
support_pmp = 0

# No debug mode (Sdext) on Sigil.
support_debug_mode = 0

# No N extension (user-level traps).
support_umode_trap = 0

support_sfence = 1

# Misaligned scalar loads/stores raise address-misaligned exceptions.
support_unaligned_load_store = 0

NUM_FLOAT_GPR = 32
NUM_GPR = 32
NUM_VEC_GPR = 32

# -----------------------------------------------------------------------------
# Vector extension configuration (Sigil: RVV 1.0 Zve64d, VLEN 512).
# pygen has no vector instruction classes, so generation stays off.
# -----------------------------------------------------------------------------
VECTOR_EXTENSION_ENABLE = 0
VLEN = 512
ELEN = 64
SELEN = 8
VELEN = int(math.log(ELEN) // math.log(2)) - 3
MAX_LMUL = 8

NUM_HARTS = 1

# misa is read-only on Sigil (IMABC FDHV SU, MXL=2). The setup patch
# makes pygen write exactly this value, which leaves Spike's writable
# misa (same value for the Sigil ISA string) unchanged too.
MISA_VALUE = 0x8000_0000_0034_11AF

# -----------------------------------------------------------------------------
# Privileged CSRs. Free-running counters (cycle/time/instret and the
# m* versions) are left out on purpose: their values differ between an
# RTL core and an instruction-set simulator by construction.
# -----------------------------------------------------------------------------
implemented_csr = [
    # Supervisor mode CSR
    privileged_reg_t.SSTATUS,
    privileged_reg_t.SIE,
    privileged_reg_t.STVEC,
    privileged_reg_t.SCOUNTEREN,
    privileged_reg_t.SSCRATCH,
    privileged_reg_t.SEPC,
    privileged_reg_t.SCAUSE,
    privileged_reg_t.STVAL,
    privileged_reg_t.SIP,
    privileged_reg_t.SATP,
    # Machine mode CSR
    privileged_reg_t.MVENDORID,
    privileged_reg_t.MARCHID,
    privileged_reg_t.MIMPID,
    privileged_reg_t.MHARTID,
    privileged_reg_t.MSTATUS,
    privileged_reg_t.MISA,
    privileged_reg_t.MEDELEG,
    privileged_reg_t.MIDELEG,
    privileged_reg_t.MIE,
    privileged_reg_t.MTVEC,
    privileged_reg_t.MCOUNTEREN,
    privileged_reg_t.MSCRATCH,
    privileged_reg_t.MEPC,
    privileged_reg_t.MCAUSE,
    privileged_reg_t.MTVAL,
    privileged_reg_t.MIP,
]

custom_csr = []
