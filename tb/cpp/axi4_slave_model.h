// AXI4 slave memory model + protocol checker for the FPGA bridge
// testbenches (issue #52): tb/cpp/axi_bridge_tb.cpp (the
// sigil_mbus_axi4 bridge alone) and tb/cpp/fpga_top_tb.cpp
// (sigil_fpga_top). Plays the role of the F2 Shell DDR4 AXI port.
//
// Timing knobs (seeded, so runs reproduce):
//   lat_min..lat_max  cycles from AR acceptance to the first R
//                     beat, and from the last W beat (with its AW)
//                     to the B response (>= 1)
//   gap_max           0..gap_max idle cycles before each further
//                     R beat (RVALID low between beats)
//   aw/w/ar_ready     probability (1..100) that AWREADY / WREADY /
//                     ARREADY is high in a given cycle
// Any data width from 8 to 64 bytes; memory is a byte array at
// [base, base+size) of the AXI address space (outside it: DECERR), or
// a SparseMem: 4 KiB pages allocated on first write over any number of
// [base, base+size) regions (the F2 map: DDR4 64 GiB at AXI 0 and HBM
// 16 GiB at AXI 0x10_0000_0000; never-written bytes read as zero).
// Writes complete when both the AW and all its W beats are in, in
// AW order; W beats may arrive before their AW. Responses (R, B)
// come back in request order.
//
// Protocol checks on the master (any violation is fatal, exit 4):
//   - AW/W/AR: once VALID is high it stays high, with every
//     payload field unchanged, until the READY handshake;
//   - WLAST exactly on beat AWLEN of each burst;
//   - AxBURST == INCR, AxSIZE <= data width, address aligned to
//     AxSIZE, no burst crossing a 4 KiB boundary;
//   - WSTRB only on the byte lanes the (possibly narrow) beat
//     addresses;
//   - (slave side, self-check) RVALID/BVALID held until READY.
// Response ordering is by construction (in-order queues, one ID);
// the testbenches check the returned data against a reference.
#ifndef SIGIL_AXI4_SLAVE_MODEL_H_
#define SIGIL_AXI4_SLAVE_MODEL_H_

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <random>
#include <unordered_map>
#include <string>
#include <type_traits>
#include <vector>

// Sparse byte-addressed memory over a set of AXI regions.
class SparseMem {
 public:
  void AddRegion(uint64_t base, uint64_t size) { regions_[base] = size; }
  bool Mapped(uint64_t a) const {
    auto it = regions_.upper_bound(a);
    if (it == regions_.begin()) return false;
    --it;
    return a - it->first < it->second;
  }
  uint8_t Read(uint64_t a) const {
    auto it = pages_.find(a >> 12);
    return it == pages_.end() ? 0 : it->second[a & 0xFFF];
  }
  void Write(uint64_t a, uint8_t v) {
    auto& p = pages_[a >> 12];
    if (!p) p.reset(new uint8_t[4096]());
    p[a & 0xFFF] = v;
  }
  void WriteBlock(uint64_t a, const uint8_t* d, size_t n) {
    for (size_t i = 0; i < n; ++i) Write(a + i, d[i]);
  }
  uint64_t Read64(uint64_t a) const {
    uint64_t v = 0;
    for (int i = 0; i < 8; ++i) v |= uint64_t(Read(a + i)) << (8 * i);
    return v;
  }
  void Write64(uint64_t a, uint64_t v) {
    for (int i = 0; i < 8; ++i) Write(a + i, uint8_t(v >> (8 * i)));
  }
  void Clear() { pages_.clear(); }
  size_t Pages() const { return pages_.size(); }

 private:
  std::map<uint64_t, uint64_t> regions_;
  std::unordered_map<uint64_t, std::unique_ptr<uint8_t[]>> pages_;
};

struct AxiConfig {
  int lat_min = 1;
  int lat_max = 1;
  int gap_max = 0;
  int aw_ready = 100;
  int w_ready = 100;
  int ar_ready = 100;
  uint64_t seed = 1;

  // "--axi-lat A:B", "--axi-gap N", "--axi-ready P" (all three
  // address/data channels), "--axi-seed S". Returns argv slots used.
  int Parse(int argc, char** argv, int i) {
    auto need = [&]() { return i + 1 < argc; };
    auto clamp = [](int p) { return p < 1 ? 1 : (p > 100 ? 100 : p); };
    if (std::strcmp(argv[i], "--axi-lat") == 0 && need()) {
      const char* s = argv[i + 1];
      const char* c = std::strchr(s, ':');
      lat_min = std::atoi(s);
      lat_max = c ? std::atoi(c + 1) : lat_min;
      if (lat_min < 1) lat_min = 1;
      if (lat_max < lat_min) lat_max = lat_min;
      return 2;
    }
    if (std::strcmp(argv[i], "--axi-gap") == 0 && need()) {
      gap_max = std::atoi(argv[i + 1]);
      return 2;
    }
    if (std::strcmp(argv[i], "--axi-ready") == 0 && need()) {
      aw_ready = w_ready = ar_ready = clamp(std::atoi(argv[i + 1]));
      return 2;
    }
    if (std::strcmp(argv[i], "--axi-seed") == 0 && need()) {
      seed = std::strtoull(argv[i + 1], nullptr, 0);
      return 2;
    }
    return 0;
  }
  std::string Describe() const {
    char b[160];
    std::snprintf(b, sizeof(b),
                  "axi lat %d:%d gap %d ready aw/w/ar %d/%d/%d%% seed %llu",
                  lat_min, lat_max, gap_max, aw_ready, w_ready, ar_ready,
                  static_cast<unsigned long long>(seed));
    return b;
  }
};

// Master-driven signals, sampled before the rising edge.
struct AxiM {
  bool awvalid = false, wvalid = false, bready = false;
  bool arvalid = false, rready = false, wlast = false;
  uint64_t awaddr = 0, araddr = 0, wstrb = 0;
  uint32_t awid = 0, arid = 0;
  uint8_t awlen = 0, awsize = 0, awburst = 0, awcache = 0, awprot = 0;
  uint8_t arlen = 0, arsize = 0, arburst = 0, arcache = 0, arprot = 0;
  uint8_t awlock = 0, awqos = 0, arlock = 0, arqos = 0;
  uint8_t wdata[64] = {};
};
// Slave-driven signals for one cycle.
struct AxiS {
  bool awready = false, wready = false, arready = false;
  bool bvalid = false, rvalid = false, rlast = false;
  uint32_t bid = 0, rid = 0;
  uint8_t bresp = 0, rresp = 0;
  uint8_t rdata[64] = {};
};

class Axi4SlaveModel {
 public:
  // Called for every W beat applied to memory: AXI byte address of
  // the data-width-aligned block, its bytes and byte strobes.
  using WriteObserver =
      std::function<void(uint64_t block, const uint8_t* data, uint64_t strb)>;

  Axi4SlaveModel(const AxiConfig& cfg, int dw_bytes, uint64_t base,
                 std::vector<uint8_t>* mem)
      : cfg_(cfg), dw_(dw_bytes), base_(base), mem_(mem), rng_(cfg.seed) {
    lb_ = 0;
    while ((1 << lb_) < dw_) lb_++;
  }
  Axi4SlaveModel(const AxiConfig& cfg, int dw_bytes, SparseMem* sparse)
      : cfg_(cfg), dw_(dw_bytes), base_(0), mem_(nullptr), sparse_(sparse),
        rng_(cfg.seed) {
    lb_ = 0;
    while ((1 << lb_) < dw_) lb_++;
  }
  void SetWriteObserver(WriteObserver f) { obs_ = std::move(f); }

  AxiS Outputs() {
    AxiS s{};
    s.awready = Roll(cfg_.aw_ready);
    s.wready = Roll(cfg_.w_ready);
    s.arready = Roll(cfg_.ar_ready);
    if (!bq_.empty() && bq_.front().ready_at <= now_) {
      s.bvalid = true;
      s.bid = bq_.front().id;
      s.bresp = bq_.front().resp;
    }
    if (!rq_.empty() && rq_.front().ready_at <= now_) {
      const RBeat& r = rq_.front();
      s.rvalid = true;
      s.rid = r.id;
      s.rresp = r.resp;
      s.rlast = r.last;
      std::memcpy(s.rdata, r.data, size_t(dw_));
    }
    // Slave-side self-check: a shown response stays until taken.
    if (last_.bvalid && !last_m_.bready && !s.bvalid) Fail("BVALID dropped");
    if (last_.rvalid && !last_m_.rready && !s.rvalid) Fail("RVALID dropped");
    cur_ = s;
    return s;
  }

  void Edge(const AxiM& m) {
    const AxiS& s = cur_;
    CheckStable(m, s);
    // Stall statistics (VALID && !READY).
    if (m.awvalid && !s.awready) aw_stall_++;
    if (m.wvalid && !s.wready) w_stall_++;
    if (m.arvalid && !s.arready) ar_stall_++;
    if (s.rvalid && !m.rready) r_stall_++;
    if (s.bvalid && !m.bready) b_stall_++;
    // Responses retired this cycle.
    if (s.bvalid && m.bready) {
      bq_.pop_front();
      b_count_++;
    }
    if (s.rvalid && m.rready) {
      rq_.pop_front();
      r_beats_++;
      if (!rq_.empty() && rq_.front().ready_at <= now_ + 1) {
        rq_.front().ready_at = now_ + 1 + uint64_t(Rand(0, cfg_.gap_max));
      }
    }
    // Requests.
    if (m.arvalid && s.arready) {
      CheckBurst("AR", m.araddr, m.arlen, m.arsize, m.arburst);
      ar_count_++;
      last_arprot_ = m.arprot;
      const uint64_t first =
          now_ + uint64_t(Rand(cfg_.lat_min, cfg_.lat_max));
      // Beats queued behind earlier ones; only the first beat of
      // this burst carries the latency, the rest the gap.
      uint64_t at = first;
      for (int i = 0; i <= m.arlen; ++i) {
        RBeat b{};
        b.id = m.arid;
        b.last = (i == m.arlen);
        const uint64_t a = BeatAddr(m.araddr, m.arsize, i);
        const uint64_t blk = a & ~uint64_t(dw_ - 1);
        b.resp = InMem(blk) ? 0 : 3;
        for (int k = 0; k < dw_; ++k) {
          b.data[k] = InMem(blk + k) ? MemRead(blk + k) : 0;
        }
        b.ready_at = at;
        at = 0;  // later beats: set when the previous one retires
        rq_.push_back(b);
      }
      // Reads see memory as of acceptance: the bridge issues one
      // transaction at a time, and B is only sent after the write
      // is applied, so no read can overtake a write.
    }
    if (m.awvalid && s.awready) {
      CheckBurst("AW", m.awaddr, m.awlen, m.awsize, m.awburst);
      Aw aw{m.awaddr, m.awid, m.awlen, m.awsize, 0};
      awq_.push_back(aw);
      aw_count_++;
    }
    if (m.wvalid && s.wready) {
      WBeat w{};
      std::memcpy(w.data, m.wdata, size_t(dw_));
      w.strb = m.wstrb;
      w.last = m.wlast;
      wq_.push_back(w);
      w_beats_++;
    }
    DrainWrites();
    last_ = s;
    last_m_ = m;
    now_++;
  }

  bool Idle() const {
    return rq_.empty() && bq_.empty() && awq_.empty() && wq_.empty();
  }
  uint8_t last_arprot() const { return last_arprot_; }
  std::string Stats() const {
    char b[320];
    std::snprintf(b, sizeof(b),
        "AXI: %llu AR (%llu R beats), %llu AW (%llu W beats, %llu B); "
        "stall cycles AW %llu W %llu AR %llu R %llu B %llu",
        U(ar_count_), U(r_beats_), U(aw_count_), U(w_beats_), U(b_count_),
        U(aw_stall_), U(w_stall_), U(ar_stall_), U(r_stall_), U(b_stall_));
    return b;
  }

 private:
  struct RBeat {
    uint32_t id;
    uint8_t resp;
    bool last;
    uint64_t ready_at;
    uint8_t data[64];
  };
  struct BResp {
    uint32_t id;
    uint8_t resp;
    uint64_t ready_at;
  };
  struct Aw {
    uint64_t addr;
    uint32_t id;
    uint8_t len, size;
    int beats_done;
    bool err = false;
  };
  struct WBeat {
    uint8_t data[64];
    uint64_t strb;
    bool last;
  };
  static unsigned long long U(uint64_t v) {
    return static_cast<unsigned long long>(v);
  }
  [[noreturn]] void Fail(const char* what) const {
    std::fprintf(stderr, "AXI PROTOCOL ERROR at AXI cycle %llu: %s\n",
                 U(now_), what);
    std::exit(4);
  }
  bool InMem(uint64_t a) const {
    if (sparse_) return sparse_->Mapped(a);
    return a >= base_ && a - base_ < mem_->size();
  }
  uint8_t MemRead(uint64_t a) const {
    return sparse_ ? sparse_->Read(a) : (*mem_)[a - base_];
  }
  void MemWrite(uint64_t a, uint8_t v) {
    if (sparse_) sparse_->Write(a, v);
    else (*mem_)[a - base_] = v;
  }
  static uint64_t BeatAddr(uint64_t addr, uint8_t size, int i) {
    const uint64_t n = uint64_t(1) << size;
    return i == 0 ? addr : (addr & ~(n - 1)) + uint64_t(i) * n;
  }
  void CheckBurst(const char* ch, uint64_t addr, uint8_t len, uint8_t size,
                  uint8_t burst) const {
    char b[200];
    if (burst != 1) {
      std::snprintf(b, sizeof(b), "%sBURST %u (only INCR expected)", ch, burst);
      Fail(b);
    }
    if (size > lb_) {
      std::snprintf(b, sizeof(b), "%sSIZE %u wider than the %d-byte bus", ch,
                    size, dw_);
      Fail(b);
    }
    const uint64_t n = uint64_t(1) << size;
    if (addr & (n - 1)) {
      std::snprintf(b, sizeof(b), "%sADDR 0x%llx not aligned to size %u", ch,
                    U(addr), size);
      Fail(b);
    }
    if ((addr & 0xFFF) + (uint64_t(len) + 1) * n > 0x1000) {
      std::snprintf(b, sizeof(b), "%s burst 0x%llx len %u size %u crosses 4 KiB",
                    ch, U(addr), len, size);
      Fail(b);
    }
  }
  void CheckStable(const AxiM& m, const AxiS&) {
    const AxiM& p = last_m_;
    const AxiS& ps = last_;
    if (p.awvalid && !ps.awready) {
      if (!m.awvalid || m.awaddr != p.awaddr || m.awid != p.awid ||
          m.awlen != p.awlen || m.awsize != p.awsize ||
          m.awburst != p.awburst || m.awcache != p.awcache ||
          m.awprot != p.awprot || m.awlock != p.awlock || m.awqos != p.awqos)
        Fail("AW channel changed while AWVALID && !AWREADY");
    }
    if (p.wvalid && !ps.wready) {
      if (!m.wvalid || m.wstrb != p.wstrb || m.wlast != p.wlast ||
          std::memcmp(m.wdata, p.wdata, size_t(dw_)) != 0)
        Fail("W channel changed while WVALID && !WREADY");
    }
    if (p.arvalid && !ps.arready) {
      if (!m.arvalid || m.araddr != p.araddr || m.arid != p.arid ||
          m.arlen != p.arlen || m.arsize != p.arsize ||
          m.arburst != p.arburst || m.arcache != p.arcache ||
          m.arprot != p.arprot || m.arlock != p.arlock || m.arqos != p.arqos)
        Fail("AR channel changed while ARVALID && !ARREADY");
    }
  }
  void DrainWrites() {
    while (!awq_.empty() && !wq_.empty()) {
      Aw& aw = awq_.front();
      const WBeat w = wq_.front();
      wq_.pop_front();
      const int i = aw.beats_done;
      if (w.last != (i == aw.len)) {
        char b[160];
        std::snprintf(b, sizeof(b),
                      "WLAST=%d on beat %d of a %u-beat burst (AWADDR 0x%llx)",
                      w.last, i, unsigned(aw.len) + 1, U(aw.addr));
        Fail(b);
      }
      const uint64_t a = BeatAddr(aw.addr, aw.size, i);
      const uint64_t blk = a & ~uint64_t(dw_ - 1);
      const int lo = int(a - blk), n = 1 << aw.size;
      for (int k = 0; k < dw_; ++k) {
        if (!((w.strb >> k) & 1)) continue;
        if (k < lo || k >= lo + n) {
          char b[160];
          std::snprintf(b, sizeof(b),
                        "WSTRB 0x%llx outside the active lanes [%d,%d) of beat "
                        "%d (AWADDR 0x%llx size %u)",
                        U(w.strb), lo, lo + n, i, U(aw.addr), aw.size);
          Fail(b);
        }
        if (InMem(blk + k)) {
          MemWrite(blk + k, w.data[k]);
        } else {
          aw.err = true;
        }
      }
      if (obs_) obs_(blk, w.data, w.strb);
      if (++aw.beats_done > aw.len) {
        BResp r{aw.id, uint8_t(aw.err ? 3 : 0),
                now_ + uint64_t(Rand(cfg_.lat_min, cfg_.lat_max))};
        bq_.push_back(r);
        awq_.pop_front();
      }
    }
    // Leftover W beats wait for their AW (allowed by AXI).
  }
  bool Roll(int pct) {
    if (pct >= 100) return true;
    return int(rng_() % 100) < pct;
  }
  int Rand(int lo, int hi) {
    if (hi <= lo) return lo;
    return lo + int(rng_() % uint64_t(hi - lo + 1));
  }

  AxiConfig cfg_;
  int dw_, lb_;
  uint64_t base_;
  std::vector<uint8_t>* mem_;
  SparseMem* sparse_ = nullptr;
  std::mt19937_64 rng_;
  WriteObserver obs_;
  std::deque<RBeat> rq_;
  std::deque<BResp> bq_;
  std::deque<Aw> awq_;
  std::deque<WBeat> wq_;
  AxiS cur_{}, last_{};
  AxiM last_m_{};
  uint8_t last_arprot_ = 0;
  uint64_t now_ = 0;
  uint64_t ar_count_ = 0, r_beats_ = 0, aw_count_ = 0, w_beats_ = 0;
  uint64_t b_count_ = 0;
  uint64_t aw_stall_ = 0, w_stall_ = 0, ar_stall_ = 0, r_stall_ = 0;
  uint64_t b_stall_ = 0;
};

// ---- Verilator glue (ports named m_axi_* as in sigil_mbus_axi4) ----
namespace axi_detail {
template <typename T>
void ToBytes(const T& v, uint8_t* out, int n) {
  if constexpr (std::is_integral_v<T>) {
    for (int i = 0; i < n; ++i) out[i] = uint8_t(uint64_t(v) >> (8 * i));
  } else {
    for (int i = 0; i < n; ++i) out[i] = uint8_t(v[i / 4] >> (8 * (i % 4)));
  }
}
template <typename T>
void FromBytes(T& v, const uint8_t* in, int n) {
  if constexpr (std::is_integral_v<T>) {
    uint64_t x = 0;
    for (int i = 0; i < n; ++i) x |= uint64_t(in[i]) << (8 * i);
    v = static_cast<T>(x);
  } else {
    for (int w = 0; w < (n + 3) / 4; ++w) {
      uint32_t x = 0;
      for (int k = 0; k < 4 && 4 * w + k < n; ++k) {
        x |= uint32_t(in[4 * w + k]) << (8 * k);
      }
      v[w] = x;
    }
  }
}
}  // namespace axi_detail

template <typename Top>
void AxiDrive(const AxiS& s, Top* dut, int dw) {
  dut->m_axi_awready = s.awready;
  dut->m_axi_wready = s.wready;
  dut->m_axi_arready = s.arready;
  dut->m_axi_bvalid = s.bvalid;
  dut->m_axi_bid = s.bid;
  dut->m_axi_bresp = s.bresp;
  dut->m_axi_rvalid = s.rvalid;
  dut->m_axi_rid = s.rid;
  dut->m_axi_rresp = s.rresp;
  dut->m_axi_rlast = s.rlast;
  axi_detail::FromBytes(dut->m_axi_rdata, s.rdata, dw);
}
template <typename Top>
AxiM AxiSample(Top* dut, int dw) {
  AxiM m;
  m.awvalid = dut->m_axi_awvalid;
  m.awaddr = dut->m_axi_awaddr;
  m.awid = dut->m_axi_awid;
  m.awlen = dut->m_axi_awlen;
  m.awsize = dut->m_axi_awsize;
  m.awburst = dut->m_axi_awburst;
  m.awcache = dut->m_axi_awcache;
  m.awprot = dut->m_axi_awprot;
  m.awlock = dut->m_axi_awlock;
  m.awqos = dut->m_axi_awqos;
  m.wvalid = dut->m_axi_wvalid;
  m.wlast = dut->m_axi_wlast;
  m.wstrb = uint64_t(dut->m_axi_wstrb);
  axi_detail::ToBytes(dut->m_axi_wdata, m.wdata, dw);
  m.bready = dut->m_axi_bready;
  m.arvalid = dut->m_axi_arvalid;
  m.araddr = dut->m_axi_araddr;
  m.arid = dut->m_axi_arid;
  m.arlen = dut->m_axi_arlen;
  m.arsize = dut->m_axi_arsize;
  m.arburst = dut->m_axi_arburst;
  m.arcache = dut->m_axi_arcache;
  m.arprot = dut->m_axi_arprot;
  m.arlock = dut->m_axi_arlock;
  m.arqos = dut->m_axi_arqos;
  m.rready = dut->m_axi_rready;
  return m;
}

#endif  // SIGIL_AXI4_SLAVE_MODEL_H_
