// DPI side of tb/sv/sigil_oops_chk.sv (issue #73 oops hunt): an
// architectural shadow of every cacheable 64-bit word the core's
// data port has stored or loaded, checked against every later
// load response and (relative to FENCE.I) every fetch response.
// Reports go to stdout prefixed "OOPSCHK"; the first
// OOPSCHK_MAX (env, default 40) of each kind are printed and all
// are counted. OOPSCHK_FATAL=1 exits the simulation (status 4) at
// the first report.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <unordered_map>

namespace {
struct Word {
  uint64_t val = 0;
  uint64_t st_cyc = 0;     // cycle of the last store (0 = none)
  uint64_t st_epoch = 0;   // FENCE.I count when it was stored
  uint8_t known = 0;       // byte lanes with a known value
};
struct Page {
  Word w[512];
};
std::unordered_map<uint64_t, std::unique_ptr<Page>> g_pages;
uint64_t g_epoch = 0;
uint64_t g_loads = 0, g_stores = 0, g_fetches = 0, g_walk_rsp_stale = 0;
uint64_t g_dmism = 0, g_imism = 0;
long g_max = -1;
int g_fatal = -1;

long MaxReports() {
  if (g_max < 0) {
    const char* e = std::getenv("OOPSCHK_MAX");
    g_max = e ? std::atol(e) : 40;
  }
  return g_max;
}
void MaybeFatal() {
  if (g_fatal < 0) {
    const char* e = std::getenv("OOPSCHK_FATAL");
    g_fatal = (e && e[0] == '1') ? 1 : 0;
  }
  if (g_fatal == 1) {
    std::printf("OOPSCHK FATAL: stopping at the first report\n");
    std::fflush(stdout);
    std::exit(4);
  }
}
Word& W(uint64_t pa) {
  auto& p = g_pages[pa >> 12];
  if (!p) p.reset(new Page());
  return p->w[(pa >> 3) & 511];
}
uint64_t LaneMask(uint8_t be) {
  uint64_t m = 0;
  for (int i = 0; i < 8; ++i) {
    if (be & (1u << i)) m |= 0xFFull << (8 * i);
  }
  return m;
}
}  // namespace

extern "C" long long oops_epoch() { return static_cast<long long>(g_epoch); }

extern "C" void oops_fencei(long long) { ++g_epoch; }

extern "C" void oops_d_store(long long cyc, long long pa, long long data, int be,
                             int walk) {
  (void)walk;
  ++g_stores;
  Word& w = W(static_cast<uint64_t>(pa));
  const uint64_t m = LaneMask(static_cast<uint8_t>(be));
  w.val = (w.val & ~m) | (static_cast<uint64_t>(data) & m);
  w.known |= static_cast<uint8_t>(be);
  w.st_cyc = static_cast<uint64_t>(cyc);
  w.st_epoch = g_epoch;
}

extern "C" void oops_d_load(long long cyc, long long pa, long long data, int walk) {
  ++g_loads;
  Word& w = W(static_cast<uint64_t>(pa));
  const uint64_t m = LaneMask(w.known);
  const uint64_t got = static_cast<uint64_t>(data);
  if ((got & m) != (w.val & m)) {
    ++g_dmism;
    if (static_cast<long>(g_dmism) <= MaxReports()) {
      std::printf("OOPSCHK d-load-mismatch cyc=%llu pa=0x%llx got=0x%016llx exp=0x%016llx "
                  "known=0x%02x last_store_cyc=%llu walker=%d\n",
                  static_cast<unsigned long long>(cyc),
                  static_cast<unsigned long long>(pa),
                  static_cast<unsigned long long>(got),
                  static_cast<unsigned long long>(w.val), w.known,
                  static_cast<unsigned long long>(w.st_cyc), walk);
      std::fflush(stdout);
    }
    MaybeFatal();
  }
  // Learn the unknown lanes (and resync after a report).
  w.val = got;
  w.known = 0xFF;
}

extern "C" void oops_i_fetch(long long cyc, long long pa, int data, long long epoch) {
  ++g_fetches;
  Word& w = W(static_cast<uint64_t>(pa));
  const int sh = (pa & 4) ? 32 : 0;
  const uint8_t lanes = (pa & 4) ? 0xF0 : 0x0F;
  if ((w.known & lanes) != lanes || w.st_cyc == 0) return;
  const uint32_t exp = static_cast<uint32_t>(w.val >> sh);
  const uint32_t got = static_cast<uint32_t>(data);
  if (got != exp && w.st_epoch < static_cast<uint64_t>(epoch)) {
    ++g_imism;
    if (static_cast<long>(g_imism) <= MaxReports()) {
      std::printf("OOPSCHK i-fetch-stale cyc=%llu pa=0x%llx got=0x%08x exp=0x%08x "
                  "store_cyc=%llu store_epoch=%llu fetch_epoch=%lld\n",
                  static_cast<unsigned long long>(cyc),
                  static_cast<unsigned long long>(pa), got, exp,
                  static_cast<unsigned long long>(w.st_cyc),
                  static_cast<unsigned long long>(w.st_epoch), epoch);
      std::fflush(stdout);
    }
    MaybeFatal();
  }
}

extern "C" void oops_stale_walk(long long cyc, long long req_pa, int req_we,
                                long long walker_pa, int walker_we, long long data,
                                int is_data, long long va, int level, int priv,
                                long long fva, long long dva) {
  ++g_walk_rsp_stale;
  if (static_cast<long>(g_walk_rsp_stale) <= MaxReports()) {
    std::printf("OOPSCHK stale-walk-rsp cyc=%llu req_pa=0x%llx req_we=%d "
                "walker_pa=0x%llx walker_we=%d data=0x%016llx walker_is_data=%d "
                "walker_va=0x%llx level=%d priv=%d fetch_va=0x%llx mem_va=0x%llx\n",
                static_cast<unsigned long long>(cyc),
                static_cast<unsigned long long>(req_pa), req_we,
                static_cast<unsigned long long>(walker_pa), walker_we,
                static_cast<unsigned long long>(data), is_data,
                static_cast<unsigned long long>(va), level, priv,
                static_cast<unsigned long long>(fva),
                static_cast<unsigned long long>(dva));
    std::fflush(stdout);
  }
  MaybeFatal();
}

extern "C" void oops_summary() {
  std::printf("OOPSCHK summary: d-loads %llu d-stores %llu fetches %llu fencei %llu | "
              "d-load-mismatch %llu i-fetch-stale %llu stale-walk-rsp %llu\n",
              static_cast<unsigned long long>(g_loads),
              static_cast<unsigned long long>(g_stores),
              static_cast<unsigned long long>(g_fetches),
              static_cast<unsigned long long>(g_epoch),
              static_cast<unsigned long long>(g_dmism),
              static_cast<unsigned long long>(g_imism),
              static_cast<unsigned long long>(g_walk_rsp_stale));
  std::fflush(stdout);
}
