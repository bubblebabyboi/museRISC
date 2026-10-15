// Unit test for muserisc_csr: CSR read/write semantics and masks,
// trap entry/return state updates, delegation, interrupt priority
// and steering, counters, and the PMP match matrix — all against
// spec-derived expectations, driving the module's own ports.
#include "Vmuserisc_csr.h"
#include "verilated.h"
#include "verilated_cov.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <memory>

static uint64_t g_checks = 0;
static bool g_fail = false;

#define CHECK(cond)                                                     \
  do {                                                                  \
    ++g_checks;                                                         \
    if (!(cond)) {                                                      \
      std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);       \
      g_fail = true;                                                    \
      return 1;                                                         \
    }                                                                   \
  } while (0)

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vmuserisc_csr> d{new Vmuserisc_csr{&context}};
  const char* cov_path = std::getenv("COV_FILE");

  auto tick = [&]() {
    d->clk_i = 0; d->eval();
    d->clk_i = 1; d->eval();
    d->clk_i = 0; d->eval();
  };
  auto rd = [&](uint16_t addr) {
    d->addr_i = addr;
    d->wr_en_i = 0;
    d->eval();
    return d->rdata_o;
  };
  auto wr = [&](uint16_t addr, uint64_t value) {
    d->addr_i = addr;
    d->wdata_i = value;
    d->wr_en_i = 1;
    tick();
    d->wr_en_i = 0;
    d->eval();
  };
  auto illegal = [&](uint16_t addr, bool write) {
    d->addr_i = addr;
    d->wr_en_i = write ? 1 : 0;
    d->eval();
    const bool ill = d->illegal_o != 0;
    d->wr_en_i = 0;
    return ill;
  };

  d->clk_i = 0;
  d->rst_ni = 0;
  d->addr_i = 0;
  d->wdata_i = 0;
  d->wr_en_i = 0;
  d->sys_op_i = 0;
  d->ret_en_i = 0;
  d->trap_take_i = 0;
  d->trap_cause_i = 0;
  d->trap_pc_i = 0;
  d->trap_tval_i = 0;
  d->trap_gpa_i = 0;
  d->trap_gva_i = 0;
  d->trap_tinst_i = 0;
  d->vset_en_i = 0;
  d->vset_avl_i = 0;
  d->vset_vtype_i = 0;
  d->vset_keep_vl_i = 0;
  d->vset_vlmax_i = 0;
  d->vec_dirty_i = 0;
  d->irq_m_timer_i = 0;
  d->irq_m_soft_i = 0;
  d->irq_m_ext_i = 0;
  d->irq_s_timer_i = 0;
  d->irq_s_ext_i = 0;
  d->retire_i = 0;
  d->pmp_addr_a_i = 0;
  d->pmp_acc_a_i = 0;
  d->pmp_priv_a_i = 0;
  d->pmp_addr_b_i = 0;
  d->pmp_acc_b_i = 0;
  d->pmp_priv_b_i = 0;
  d->pmp_addr_c_i = 0;
  d->pmp_acc_c_i = 0;
  d->pmp_priv_c_i = 1;  // walker port is checked as S-mode
  tick();
  tick();
  d->rst_ni = 1;
  d->eval();

  // Reset state: M-mode, everything zero, misa constant.
  CHECK(d->priv_o == 3);
  CHECK(rd(0x301) == 0x80000000003411AFULL);  // misa RV64 IMABC FDHV SU
  CHECK(rd(0x300) == ((2ull << 34) | (2ull << 32)));  // mstatus: SXL/UXL only
  CHECK(rd(0xF14) == 0);                     // mhartid
  CHECK(illegal(0x7c0, false));              // nonexistent CSR
  CHECK(illegal(0xF11, true));               // read-only class (0xC00-0xFFF)
  CHECK(!illegal(0xF11, false));
  CHECK(!illegal(0x301, true));              // misa writes are WARL-ignored
  wr(0x301, 0);
  CHECK(rd(0x301) == 0x80000000003411AFULL);
  CHECK(!illegal(0x340, true));              // mscratch rw

  // Plain storage CSRs round-trip.
  wr(0x340, 0xdeadbeefcafef00dULL);
  CHECK(rd(0x340) == 0xdeadbeefcafef00dULL);
  wr(0x140, 0x1122334455667788ULL);
  CHECK(rd(0x140) == 0x1122334455667788ULL);
  wr(0x30A, 0x5a5a5a5a5a5a5a5aULL);
  CHECK(rd(0x30A) == 0x5a5a5a5a5a5a5a5aULL);
  wr(0x10A, 0xa5a5a5a5a5a5a5a5ULL);
  CHECK(rd(0x10A) == 0xa5a5a5a5a5a5a5a5ULL);
  wr(0x306, 0xffffffffULL);
  CHECK(rd(0x306) == 0x7ULL);  // only CY|TM|IR exist
  wr(0x106, 0x7ULL);
  CHECK(rd(0x106) == 0x7ULL);

  // Masked CSRs: medeleg/mideleg/mie keep only implemented bits.
  wr(0x302, ~0ull);
  CHECK(rd(0x302) == 0xF0B75DULL);  // + VS-ecall/guest/virtual bits
  wr(0x303, ~0ull);
  CHECK(rd(0x303) == 0x666ULL);  // 222 writable + VS bits always delegated
  wr(0x304, ~0ull);
  CHECK(rd(0x304) == 0xEEEULL);  // + hie aliases (VSSIE/VSTIE/VSEIE)
  wr(0x302, 0);
  wr(0x303, 0);
  wr(0x304, 0);

  // mtvec mode WARL: modes 2/3 read back 0; alignment of base.
  wr(0x305, 0x1003);
  CHECK(rd(0x305) == 0x1000);
  wr(0x305, 0x1001);
  CHECK(rd(0x305) == 0x1001);

  // mepc/sepc low bits are masked (IALIGN=32).
  wr(0x341, 0x12345);
  CHECK(rd(0x341) == 0x12344);
  wr(0x141, 0x999);
  CHECK(rd(0x141) == 0x998);

  // mstatus field handling: MPP=2 (reserved) reads back 0; sstatus
  // is a masked view; sstatus writes touch only S-visible fields.
  wr(0x300, (2ull << 11) | (1ull << 3) | (1ull << 17));
  CHECK(((rd(0x300) >> 11) & 3) == 0);
  CHECK(((rd(0x300) >> 3) & 1) == 1);
  wr(0x300, (1ull << 17));  // MIE back to 0 so the next check can tell
  wr(0x100, (1ull << 1) | (1ull << 18) | (1ull << 3));  // bit3 must not land
  CHECK(((rd(0x300) >> 1) & 1) == 1);   // SIE set via sstatus
  CHECK(((rd(0x300) >> 18) & 1) == 1);  // SUM set via sstatus
  CHECK(((rd(0x300) >> 3) & 1) == 0);   // MIE not writable via sstatus
  wr(0x300, 0);
  CHECK((rd(0x100) & ~(3ull << 32)) == 0);

  // Counters: mcycle free-runs, inhibit works, minstret counts.
  const uint64_t c0 = rd(0xB00);
  tick();
  tick();
  CHECK(rd(0xB00) >= c0 + 2);
  wr(0xB00, 1000);
  CHECK(rd(0xC00) >= 1000 && rd(0xC00) <= 1010);
  CHECK(rd(0xC01) < 1000);  // time is not an mcycle alias
  wr(0xB02, 500);
  d->retire_i = 1;
  tick();
  tick();
  d->retire_i = 0;
  CHECK(rd(0xB02) == 502);
  CHECK(rd(0xC02) == 502);
  wr(0x320, 0x5);  // inhibit cycle + instret
  const uint64_t ci = rd(0xB00);
  const uint64_t ti = rd(0xC01);
  d->retire_i = 1;
  tick();
  tick();
  tick();
  d->retire_i = 0;
  CHECK(rd(0xB00) == ci);
  CHECK(rd(0xC01) >= ti + 3);  // real time is not CY-inhibited
  CHECK(rd(0xB02) == 502);
  wr(0x320, 0);
  CHECK(rd(0xB03) == 0);  // mhpmcounter3 reads zero
  wr(0xB03, 12345);
  CHECK(rd(0xB03) == 0);
  CHECK(!illegal(0xB03, true));

  // Interrupt selection: priority and delegation steering.
  wr(0x304, (1ull << 7) | (1ull << 11) | (1ull << 5));  // MTIE|MEIE|STIE
  wr(0x300, (1ull << 3));                               // mstatus.MIE
  d->irq_m_timer_i = 1;
  d->irq_m_ext_i = 1;
  d->eval();
  CHECK(d->irq_valid_o);
  CHECK(d->irq_cause_o == (0x8000000000000000ULL | 11));  // MEI wins
  d->irq_m_ext_i = 0;
  d->eval();
  CHECK(d->irq_cause_o == (0x8000000000000000ULL | 7));   // then MTI
  wr(0x303, (1ull << 5));                                 // delegate STI
  d->irq_m_timer_i = 0;
  d->irq_s_timer_i = 1;
  d->eval();
  CHECK(!d->irq_valid_o);  // delegated: not taken while in M
  d->irq_s_timer_i = 0;
  wr(0x304, 0);
  wr(0x303, 0);
  wr(0x300, 0);

  // Trap entry to M: epc/cause/tval/status shuffle.
  wr(0x305, 0x2000);  // mtvec direct
  wr(0x300, (1ull << 3) | (1ull << 17));  // MIE + MPRV
  d->trap_take_i = 1;
  d->trap_cause_i = 4;
  d->trap_pc_i = 0x800;
  d->trap_tval_i = 0x1003;
  d->eval();
  CHECK(d->trap_target_o == 0x2000);
  CHECK(d->trap_priv_o == 3);
  tick();
  d->trap_take_i = 0;
  CHECK(rd(0x341) == 0x800);
  CHECK(rd(0x342) == 4);
  CHECK(rd(0x343) == 0x1003);
  CHECK(((rd(0x300) >> 7) & 1) == 1);   // MPIE = old MIE
  CHECK(((rd(0x300) >> 3) & 1) == 0);   // MIE cleared
  CHECK(((rd(0x300) >> 11) & 3) == 3);  // MPP = M
  CHECK(((rd(0x300) >> 17) & 1) == 1);  // MPRV survives trap entry

  // Vectored target: base + 4*code for interrupts only.
  wr(0x305, 0x2001);
  d->trap_take_i = 1;
  d->trap_cause_i = 0x8000000000000007ULL;
  d->trap_pc_i = 0x900;
  d->eval();
  CHECK(d->trap_target_o == 0x2000 + 28);
  d->trap_cause_i = 2;
  d->eval();
  CHECK(d->trap_target_o == 0x2000);  // exceptions ignore vectoring
  tick();
  d->trap_take_i = 0;
  wr(0x305, 0x2000);

  // MRET: back to MPP privilege, MIE restored from MPIE.
  wr(0x341, 0x400);
  wr(0x300, (3ull << 11) | (1ull << 7));     // MPP=M, MPIE=1, MIE=0
  d->sys_op_i = 1;
  d->eval();
  CHECK(!d->sys_illegal_o);
  CHECK(d->xret_pc_o == 0x400);
  d->ret_en_i = 1;
  tick();
  d->ret_en_i = 0;
  d->sys_op_i = 0;
  CHECK(d->priv_o == 3);
  CHECK(((rd(0x300) >> 3) & 1) == 1);

  // Drop to S via MRET (MPP=S), then S-mode behavior.
  wr(0x341, 0x800);
  wr(0x300, (1ull << 11) | (1ull << 7));
  d->sys_op_i = 1;
  d->ret_en_i = 1;
  tick();
  d->ret_en_i = 0;
  d->sys_op_i = 0;
  d->eval();
  CHECK(d->priv_o == 1);
  CHECK(illegal(0x300, false));   // mstatus not readable from S
  CHECK(!illegal(0x100, false));  // sstatus is
  CHECK(!illegal(0x180, true));   // satp writable from S
  // SRET illegal in S when TSR=1 (set TSR while back in M later);
  // with TSR=0 SRET is legal in S but illegal MRET is not.
  d->sys_op_i = 1;
  d->eval();
  CHECK(d->sys_illegal_o);        // MRET from S
  d->sys_op_i = 2;
  d->eval();
  CHECK(!d->sys_illegal_o);       // SRET from S ok
  d->sys_op_i = 0;

  // Delegated exception from S goes to S (medeleg bit 8).
  wr(0x105, 0x3000);              // stvec (writable from S)
  // medeleg can only be written from M; write it after returning.
  // First get back to M: trap with a non-delegated cause.
  d->trap_take_i = 1;
  d->trap_cause_i = 2;
  d->trap_pc_i = 0x800;
  d->trap_tval_i = 0;
  d->eval();
  CHECK(d->trap_priv_o == 3);
  tick();
  d->trap_take_i = 0;
  d->eval();
  CHECK(d->priv_o == 3);
  CHECK(((rd(0x300) >> 11) & 3) == 1);  // MPP = S
  wr(0x302, (1ull << 8));
  // Drop to S again and trap with cause 8: must land in S.
  wr(0x341, 0x800);
  wr(0x300, (1ull << 11) | (1ull << 7));
  d->sys_op_i = 1;
  d->ret_en_i = 1;
  tick();
  d->ret_en_i = 0;
  d->sys_op_i = 0;
  d->trap_take_i = 1;
  d->trap_cause_i = 8;
  d->trap_pc_i = 0x810;
  d->eval();
  CHECK(d->trap_priv_o == 1);
  CHECK(d->trap_target_o == 0x3000);
  tick();
  d->trap_take_i = 0;
  d->eval();
  CHECK(d->priv_o == 1);
  CHECK(rd(0x141) == 0x810);       // sepc
  CHECK(rd(0x142) == 8);           // scause
  // SRET to U (SPP=0 after this trap since S trapped from S->SPP=1;
  // clear SPP by writing sstatus with bit8=0 from S: allowed field).
  wr(0x100, 0);
  wr(0x141, 0x900);
  d->sys_op_i = 2;
  d->eval();
  CHECK(d->xret_pc_o == 0x900);
  d->ret_en_i = 1;
  tick();
  d->ret_en_i = 0;
  d->sys_op_i = 0;
  d->eval();
  CHECK(d->priv_o == 0);
  CHECK(illegal(0x100, false));    // sstatus from U
  CHECK(!illegal(0xC00, false));   // cycle from U ok
  // Back to M for PMP checks.
  d->trap_take_i = 1;
  d->trap_cause_i = 2;
  d->trap_pc_i = 0x900;
  tick();
  d->trap_take_i = 0;
  d->eval();
  CHECK(d->priv_o == 3);
  wr(0x302, 0);

  // PMP: no entries -> M allowed, S/U denied.
  auto pmp_a = [&](uint64_t addr, int acc, int priv) {
    d->pmp_addr_a_i = addr;
    d->pmp_acc_a_i = static_cast<uint8_t>(acc);
    d->pmp_priv_a_i = static_cast<uint8_t>(priv);
    d->eval();
    return d->pmp_allow_a_o != 0;
  };
  CHECK(pmp_a(0x1000, 0, 3));
  CHECK(!pmp_a(0x1000, 0, 1));
  CHECK(!pmp_a(0x1000, 2, 0));
  // Catch-all entry 15 NAPOT RWX: S/U allowed everywhere.
  wr(0x3BF, ~0ull);
  wr(0x3A2, (0x1full << 56));
  CHECK(pmp_a(0x1000, 0, 1));
  CHECK(pmp_a(0xdead000, 2, 0));
  // Entry 0: NAPOT 4 KiB at 0x80000, R only.
  wr(0x3B0, ((0x80000ull >> 2) | 0x1ffull));
  wr(0x3A0, (3 << 3) | 1);
  CHECK(rd(0x3A0) == ((3 << 3) | 1));
  CHECK(pmp_a(0x80000, 0, 1));        // R ok
  CHECK(!pmp_a(0x80000, 1, 1));       // W denied
  CHECK(!pmp_a(0x80fff, 2, 1));       // X denied (region edge)
  CHECK(pmp_a(0x81000, 1, 1));        // outside -> catch-all
  CHECK(pmp_a(0x80000, 1, 3));        // M bypasses unlocked entry
  // pmpcfg readback rules: reserved bits [6:5] read zero, an
  // X-only (R0 W0 X1) encoding is kept, and R0W1 clears W+X.
  wr(0x3A0, (rd(0x3A0) & ~(0xffull << 48)) | (0x64ull << 48));
  CHECK(((rd(0x3A0) >> 48) & 0xffull) == 0x04ull);
  wr(0x3A0, (rd(0x3A0) & ~(0xffull << 48)) | (0x06ull << 48));
  CHECK(((rd(0x3A0) >> 48) & 0xffull) == 0x00ull);
  // Lock entry 0: M is now checked too; cfg writes are ignored.
  wr(0x3A0, (1 << 7) | (3 << 3) | 1);
  CHECK(!pmp_a(0x80000, 1, 3));
  wr(0x3A0, 0x1f);
  CHECK((rd(0x3A0) & 0xff) == ((1 << 7) | (3 << 3) | 1));
  // TOR entry 1: [entry0 top, 0x90000) no access. Entry0 addr is
  // the NAPOT encoding; TOR uses raw pmpaddr values, so reprogram:
  // entry0 OFF cannot happen while locked; use entries 2 (TOR top
  // 0x90000 with prev = entry1 addr 0x88000).
  wr(0x3B1, (0x88000ull >> 2));
  wr(0x3B2, (0x90000ull >> 2));
  wr(0x3A0, (rd(0x3A0) & 0xff) | ((1ull << 3) << 16) | (0ull << 8));
  // entry2 cfg = TOR(01), no perms; entry1 OFF.
  CHECK(!pmp_a(0x88000, 0, 1));
  CHECK(!pmp_a(0x8ffff, 0, 1));
  CHECK(pmp_a(0x90000, 0, 1));
  // NA4 entry 3: exactly 4 bytes at 0xA0000, R only.
  wr(0x3B3, (0xA0000ull >> 2));
  wr(0x3A0, (rd(0x3A0) & ~(0xffull << 24)) | (0x11ull << 24));
  CHECK(pmp_a(0xA0000, 0, 1));
  CHECK(!pmp_a(0xA0000, 1, 1));
  CHECK(pmp_a(0xA0004, 1, 1));  // past the 4-byte grain: catch-all
  // Locked TOR entry 5 also locks pmpaddr4 (its lower bound).
  wr(0x3B4, (0xB0000ull >> 2));
  wr(0x3B5, (0xB8000ull >> 2));
  wr(0x3A0, (rd(0x3A0) & ~(0xffffull << 32)) | (0x89ull << 40));
  CHECK(((rd(0x3A0) >> 40) & 0xffull) == 0x89ull);  // entry5 locked TOR
  CHECK(((rd(0x3A0) >> 32) & 0xffull) == 0);        // entry4 itself OFF
  wr(0x3B4, (0xC0000ull >> 2));
  CHECK(rd(0x3B4) == (0xB0000ull >> 2));
  CHECK(pmp_a(0xB0000, 0, 1));   // TOR R
  CHECK(!pmp_a(0xB0000, 1, 1));  // TOR W denied

  // Remaining CSR storage + read-only identity registers.
  // Sdtrig stub: zero triggers — CSRs exist, read 0, ignore writes.
  CHECK(!illegal(0x7A0, true));
  wr(0x7A0, 5);
  CHECK(rd(0x7A0) == 0);              // tselect hardwired
  wr(0x7A1, ~0ull);
  CHECK(rd(0x7A1) == 0);              // tdata1 type = none
  CHECK(rd(0x7A4) == 0);              // tinfo
  CHECK(rd(0xF12) == 0x4D555345ULL);  // marchid "MUSE"
  CHECK(rd(0xF13) == 0x30000ULL);     // mimpid
  CHECK(rd(0xF15) == 0);              // mconfigptr
  CHECK(rd(0xC01) != rd(0xC00));      // independent time/cycle counters
  wr(0x142, 0x1234);                  // scause write port
  CHECK(rd(0x142) == 0x1234);
  wr(0x143, 0xabcd);                  // stval write port
  CHECK(rd(0x143) == 0xabcd);
  wr(0x342, 0x5678);                  // mcause write port
  CHECK(rd(0x342) == 0x5678);
  wr(0x343, 0x9abc);                  // mtval write port
  CHECK(rd(0x343) == 0x9abc);
  // sip write (SSIP) visible through mip and the delegated sip view.
  wr(0x303, (1ull << 1));
  wr(0x144, (1ull << 1));
  CHECK((rd(0x144) & (1ull << 1)) != 0);
  CHECK((rd(0x344) & (1ull << 1)) != 0);
  wr(0x144, 0);
  wr(0x303, 0);
  // satp storage reaches the MMU-facing output.
  wr(0x180, (8ull << 60) | 0x12345ull);
  CHECK(rd(0x180) == ((8ull << 60) | 0x12345ull));
  CHECK(d->satp_o == ((8ull << 60) | 0x12345ull));
  wr(0x180, 0);
  // mstatus TVM/TW/TSR storage.
  wr(0x300, (1ull << 20) | (1ull << 21) | (1ull << 22));
  CHECK((rd(0x300) & ((1ull << 20) | (1ull << 21) | (1ull << 22))) ==
        ((1ull << 20) | (1ull << 21) | (1ull << 22)));
  CHECK((d->mstatus_o & (1ull << 20)) != 0);
  wr(0x300, 0);

  // Remaining interrupt priority rungs: MSI(3), SEI(9), SSI(1).
  wr(0x304, (1ull << 3) | (1ull << 9) | (1ull << 1));
  wr(0x300, (1ull << 3));
  d->irq_m_soft_i = 1;
  d->eval();
  CHECK(d->irq_valid_o);
  CHECK(d->irq_cause_o == (0x8000000000000000ULL | 3));
  d->irq_m_soft_i = 0;
  d->irq_s_ext_i = 1;
  d->eval();
  CHECK(d->irq_cause_o == (0x8000000000000000ULL | 9));
  d->irq_s_ext_i = 0;
  wr(0x344, (1ull << 1));  // mip.SSIP software-pending
  d->eval();
  CHECK(d->irq_cause_o == (0x8000000000000000ULL | 1));
  wr(0x344, 0);
  // mip RMW base (#21): reads see pin | SW bit, but the value a
  // CSRRS/CSRRC builds on holds only the software SEIP/STIP.
  d->irq_s_ext_i = 1;
  d->irq_s_timer_i = 1;
  CHECK((rd(0x344) & 0x220) == 0x220);
  CHECK((d->rmw_rdata_o & 0x220) == 0);
  CHECK((d->rmw_rdata_o & ~0x220ull) == (d->rdata_o & ~0x220ull));
  wr(0x344, d->rmw_rdata_o | (1ull << 1));  // CSRRS mip, SSIP shape
  d->irq_s_ext_i = 0;
  d->irq_s_timer_i = 0;
  CHECK((rd(0x344) & 0x220) == 0);           // nothing latched
  wr(0x344, 0x220);                           // SW SEIP|STIP
  CHECK((rd(0x344) & 0x220) == 0x220);
  CHECK((d->rmw_rdata_o & 0x220) == 0x220);
  wr(0x344, 0);
  d->irq_s_ext_i = 1;
  rd(0x144);                                  // sip: not the mip RMW path
  CHECK(d->rmw_rdata_o == d->rdata_o);        // other CSRs: same value
  d->irq_s_ext_i = 0;
  wr(0x304, 0);
  wr(0x300, 0);

  // Counter access gating: mcounteren gates S/U, scounteren U.
  wr(0x306, 0);
  wr(0x106, 0);
  wr(0x341, 0x800);
  wr(0x300, (1ull << 11) | (1ull << 7));
  d->sys_op_i = 1;
  d->ret_en_i = 1;
  tick();
  d->ret_en_i = 0;
  d->sys_op_i = 0;
  d->eval();
  CHECK(d->priv_o == 1);
  CHECK(illegal(0xC00, false));        // mcounteren.CY = 0
  d->trap_take_i = 1;
  d->trap_cause_i = 2;
  d->trap_pc_i = 0x800;
  tick();
  d->trap_take_i = 0;
  d->eval();
  CHECK(d->priv_o == 3);
  wr(0x306, 1);                        // CY only
  wr(0x341, 0x800);
  wr(0x300, (1ull << 11) | (1ull << 7));
  d->sys_op_i = 1;
  d->ret_en_i = 1;
  tick();
  d->ret_en_i = 0;
  d->sys_op_i = 0;
  d->eval();
  CHECK(!illegal(0xC00, false));
  CHECK(illegal(0xC02, false));        // IR not enabled
  wr(0x100, 0);                        // SPP=U for the sret
  wr(0x141, 0x900);
  d->sys_op_i = 2;
  d->ret_en_i = 1;
  tick();
  d->ret_en_i = 0;
  d->sys_op_i = 0;
  d->eval();
  CHECK(d->priv_o == 0);
  CHECK(illegal(0xC00, false));        // scounteren.CY = 0
  d->trap_take_i = 1;
  d->trap_cause_i = 2;
  d->trap_pc_i = 0x900;
  tick();
  d->trap_take_i = 0;
  d->eval();
  CHECK(d->priv_o == 3);

  // fcsr/FS handling (stage 4b): FS=Off blocks FP CSRs; frm/
  // fflags/fcsr round-trip; the FPU side-band accumulates
  // flags and marks FS dirty (mstatus SD follows).
  CHECK(d->fs_o == 0);
  CHECK(illegal(0x003, false));
  wr(0x300, rd(0x300) | (1ull << 13));        // FS = Initial
  CHECK(d->fs_o == 1);
  CHECK(!illegal(0x003, false));
  wr(0x002, 3);                                // frm = RUP
  CHECK(rd(0x002) == 3 && d->frm_o == 3);
  CHECK(rd(0x003) == (3ull << 5));
  wr(0x003, (2ull << 5) | 0x15ull);            // fcsr: RDN + NV|UF|NX
  CHECK(rd(0x001) == 0x15 && d->frm_o == 2);
  wr(0x001, 0);
  d->fflags_i = 0x0A;                          // DZ|UF from the FPU
  d->fflags_we_i = 1;
  tick();
  d->fflags_we_i = 0;
  d->eval();
  CHECK(rd(0x001) == 0x0A);
  CHECK(d->fs_o == 1);
  d->fp_dirty_i = 1;
  tick();
  d->fp_dirty_i = 0;
  d->eval();
  CHECK(d->fs_o == 3);
  CHECK((rd(0x300) >> 63) == 1);               // SD
  CHECK(((rd(0x100) >> 13) & 3) == 3);         // sstatus sees FS

  // Hypervisor stage 7a: CSR banks, V transitions and
  // M -> HS -> VS trap delegation with hgatp storage only.
  CHECK(d->virt_o == 0);
  wr(0x600, ~0ull);
  CHECK(rd(0x600) == ((2ull << 32) | 0x7003c0ull));  // hstatus WARL
  wr(0x602, ~0ull);
  CHECK(rd(0x602) == 0xCB1FEull);                    // hedeleg
  wr(0x603, ~0ull);
  CHECK(rd(0x603) == 0x444ull);                      // hideleg
  wr(0x602, (1ull << 8));                            // delegate VU ecall
  wr(0x603, (1ull << 10));                           // delegate VSEI
  wr(0x302, (1ull << 8) | (1ull << 10));             // medeleg U/VS ecalls
  wr(0x303, 0x222ull);                               // mideleg HS ints
  wr(0x304, (1ull << 9) | 0x444ull);                 // mie SEI + VS ints
  wr(0x306, 7);
  wr(0x606, 7);
  wr(0x106, 7);
  wr(0x105, 0x3000);                                 // HS stvec
  wr(0x205, 0x4000);                                 // vstvec
  wr(0x200, (1ull << 8) | (1ull << 18));             // vsstatus SPP|SUM
  wr(0x280, (8ull << 60) | 0x12345ull);              // vsatp Sv39
  wr(0x680, (8ull << 60) | 0x4567ull);               // hgatp Sv39x4 value
  CHECK(d->hgatp_o == ((8ull << 60) | 0x4567ull));
  wr(0x600, (1ull << 7));                            // hstatus.SPV = 1
  wr(0x100, (1ull << 8));                            // sstatus.SPP = VS
  wr(0x141, 0x880);                                  // sepc
  // Enter HS by MRET, then VS by SRET from HS.
  wr(0x341, 0x800);
  wr(0x300, (1ull << 11) | (1ull << 8) | (1ull << 7));  // MPP=S, SPP=VS
  d->sys_op_i = 1;
  d->ret_en_i = 1;
  tick();
  d->ret_en_i = 0;
  d->sys_op_i = 0;
  d->eval();
  CHECK(d->priv_o == 1 && d->virt_o == 0);
  CHECK(!illegal(0x600, false));                     // H CSR from HS
  CHECK(!illegal(0x200, false));                     // VS CSR from HS
  for (int op = 5; op <= 7; ++op) {                  // HFENCE/HLV in HS
    d->sys_op_i = op;
    d->eval();
    CHECK(!d->sys_illegal_o && !d->virt_inst_o);
  }
  d->sys_op_i = 2;
  d->eval();
  CHECK(d->xret_pc_o == 0x880);
  d->ret_en_i = 1;
  tick();
  d->ret_en_i = 0;
  d->sys_op_i = 0;
  d->eval();
  CHECK(d->priv_o == 1 && d->virt_o == 1);           // now VS
  CHECK(d->satp_o == ((8ull << 60) | 0x12345ull));
  CHECK(rd(0x180) == ((8ull << 60) | 0x12345ull));   // satp substitutes
  CHECK(((rd(0x100) >> 18) & 1) == 1);               // vsstatus.SUM
  wr(0x140, 0xfeedfaceull);                          // -> vsscratch
  d->addr_i = 0x600; d->eval();
  CHECK(d->illegal_o && d->virt_inst_o);             // hstatus from VS
  d->addr_i = 0x200; d->eval();
  CHECK(d->illegal_o && d->virt_inst_o);             // vsstatus direct
  for (int op = 5; op <= 7; ++op) {                  // HFENCE/HLV in VS
    d->sys_op_i = op;
    d->eval();
    CHECK(d->sys_illegal_o && d->virt_inst_o);
  }
  d->sys_op_i = 0;
  d->eval();
  // Ecall-from-VS (cause 10) is medeleg-delegated to HS.
  d->trap_take_i = 1;
  d->trap_cause_i = 10;
  d->trap_pc_i = 0x884;
  d->eval();
  CHECK(d->trap_priv_o == 1 && d->trap_target_o == 0x3000);
  tick();
  d->trap_take_i = 0;
  d->eval();
  CHECK(d->priv_o == 1 && d->virt_o == 0);
  CHECK(rd(0x141) == 0x884 && rd(0x142) == 10);
  CHECK(((rd(0x600) >> 7) & 1) == 1);                // SPV
  CHECK(((rd(0x600) >> 8) & 1) == 1);                // SPVP
  CHECK(rd(0x240) == 0xfeedfaceull);                 // guest scratch
  // Return to VS, then a hedeleg-delegated U-ecall stays in VS.
  d->sys_op_i = 2;
  d->ret_en_i = 1;
  tick();
  d->ret_en_i = 0;
  d->sys_op_i = 0;
  d->eval();
  CHECK(d->priv_o == 1 && d->virt_o == 1);
  wr(0x100, 0);                                      // vsstatus.SPP = VU
  wr(0x141, 0x900);                                  // -> vsepc
  d->sys_op_i = 2;
  d->ret_en_i = 1;
  tick();
  d->ret_en_i = 0;
  d->sys_op_i = 0;
  d->eval();
  CHECK(d->priv_o == 0 && d->virt_o == 1);           // now VU
  d->addr_i = 0x100; d->eval();
  CHECK(d->illegal_o && d->virt_inst_o);             // S CSR from VU
  d->trap_take_i = 1;
  d->trap_cause_i = 8;
  d->trap_pc_i = 0x904;
  d->eval();
  CHECK(d->trap_priv_o == 1 && d->trap_target_o == 0x4000);
  tick();
  d->trap_take_i = 0;
  d->eval();
  CHECK(d->priv_o == 1 && d->virt_o == 1);           // delivered to VS
  CHECK(rd(0x141) == 0x904 && rd(0x142) == 8);       // via substitution

  // Interrupt virtualization: hvip injection, hideleg
  // routing, translated vscause, and HS priority in a guest.
  d->trap_take_i = 1;
  d->trap_cause_i = 10;
  d->trap_pc_i = 0x908;
  tick();
  d->trap_take_i = 0;
  d->eval();
  CHECK(d->priv_o == 1 && d->virt_o == 0);           // back in HS
  wr(0x603, 0x444ull);                               // hideleg all VS
  wr(0x604, 0x444ull);                               // hie all VS
  wr(0x200, (1ull << 8) | (1ull << 1));              // vsstatus SPP|SIE
  wr(0x645, (1ull << 2));                            // hvip.VSSIP
  d->eval();
  CHECK(!d->irq_valid_o);                            // delegated: no HS trap
  CHECK(rd(0x244) == (1ull << 1));                   // vsip.SSIP alias
  // A pending HS external interrupt wins over the VS one.
  wr(0x100, (1ull << 8) | (1ull << 1));              // sstatus SPP|SIE
  d->irq_s_ext_i = 1;
  d->eval();
  CHECK(d->irq_valid_o &&
        d->irq_cause_o == (0x8000000000000000ULL | 9));
  d->irq_s_ext_i = 0;
  d->eval();
  CHECK(!d->irq_valid_o);
  // Enter VS: VSSI is selected and lands translated as SSI.
  d->sys_op_i = 2;
  d->ret_en_i = 1;
  tick();
  d->ret_en_i = 0;
  d->sys_op_i = 0;
  d->eval();
  CHECK(d->priv_o == 1 && d->virt_o == 1);
  CHECK(d->irq_valid_o &&
        d->irq_cause_o == (0x8000000000000000ULL | 2));
  d->trap_cause_i = d->irq_cause_o;
  d->trap_pc_i = 0x908;
  d->eval();
  CHECK(d->trap_target_o == 0x4000);                 // vstvec
  d->trap_take_i = 1;
  tick();
  d->trap_take_i = 0;
  d->eval();
  CHECK(d->priv_o == 1 && d->virt_o == 1);
  CHECK(rd(0x142) == (0x8000000000000000ULL | 1));   // vscause SSI
  wr(0x144, 0);                                      // vsip clears VSSIP
  d->eval();
  CHECK(!d->irq_valid_o);
  // All three VS interrupts pending: VSEI has top priority.
  d->trap_take_i = 1;
  d->trap_cause_i = 10;
  d->trap_pc_i = 0x90c;
  tick();
  d->trap_take_i = 0;
  d->eval();
  wr(0x200, (1ull << 8) | (1ull << 1));
  wr(0x645, 0x444ull);
  d->sys_op_i = 2;
  d->ret_en_i = 1;
  tick();
  d->ret_en_i = 0;
  d->sys_op_i = 0;
  d->eval();
  CHECK(d->irq_valid_o &&
        d->irq_cause_o == (0x8000000000000000ULL | 10));
  // With hideleg clear for VSTI, it traps to HS as cause 6.
  d->trap_take_i = 1;
  d->trap_cause_i = 10;
  d->trap_pc_i = 0x910;
  tick();
  d->trap_take_i = 0;
  d->eval();
  wr(0x603, (1ull << 2));                            // only VSSI delegated
  wr(0x645, (1ull << 6));                            // hvip.VSTIP only
  d->sys_op_i = 2;
  d->ret_en_i = 1;
  tick();
  d->ret_en_i = 0;
  d->sys_op_i = 0;
  d->eval();
  CHECK(d->priv_o == 1 && d->virt_o == 1);
  CHECK(d->irq_valid_o &&
        d->irq_cause_o == (0x8000000000000000ULL | 6));
  d->trap_cause_i = d->irq_cause_o;
  d->trap_pc_i = 0x910;
  d->eval();
  CHECK(d->trap_target_o == 0x3000);                 // HS stvec
  d->trap_take_i = 1;
  tick();
  d->trap_take_i = 0;
  d->eval();
  CHECK(d->priv_o == 1 && d->virt_o == 0);
  CHECK(rd(0x142) == (0x8000000000000000ULL | 6));   // HS scause VSTI
  wr(0x645, 0);

  // Vector stage 8a: VS state, vset computation, vill.
  CHECK(d->vec_vs_o == 0);
  d->addr_i = 0xC21; d->eval();
  CHECK(d->illegal_o);                               // vtype while VS=Off
  wr(0x100, (1ull << 9));                            // sstatus.VS=Initial
  CHECK(d->vec_vs_o == 1);
  CHECK(rd(0xC22) == 64);                            // vlenb
  d->vset_vtype_i = 0xDB;                            // e64, m8, ta, ma
  d->vset_avl_i = 100;
  d->eval();
  CHECK(d->vset_vl_o == 64);                         // VLMAX cap
  d->vset_en_i = 1;
  tick();
  d->vset_en_i = 0;
  d->eval();
  CHECK(d->vl_o == 64 && rd(0xC21) == 0xDB);
  CHECK(d->vec_vs_o == 3);                           // dirty after vset
  d->vset_vtype_i = (4ull << 3);                     // SEW=128 > ELEN
  d->eval();
  CHECK(d->vset_vl_o == 0);
  d->vset_en_i = 1;
  tick();
  d->vset_en_i = 0;
  d->eval();
  CHECK(d->vl_o == 0 && (rd(0xC21) >> 63) == 1);     // vill
  d->vset_vtype_i = (2ull << 3) | 1;                 // e32, m2
  d->vset_vlmax_i = 1;
  d->eval();
  CHECK(d->vset_vl_o == 32);
  d->vset_en_i = 1;
  tick();
  d->vset_en_i = 0;
  d->vset_vlmax_i = 0;
  d->eval();
  CHECK(d->vl_o == 32 && rd(0xC20) == 32);

  d->final();
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  if (g_fail) return 1;
  std::printf("CSR TB PASS (%llu checks)\n",
              static_cast<unsigned long long>(g_checks));
  return 0;
}
