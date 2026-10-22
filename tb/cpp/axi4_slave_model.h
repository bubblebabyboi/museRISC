// AXI4 slave memory model + protocol checker for the FPGA bridge
// testbenches (issue #52): tb/cpp/axi_bridge_tb.cpp (the
// sigil_mbus_axi4 bridge alone) and tb/cpp/fpga_top_tb.cpp
// (sigil_fpga_top). Plays the role of the F2 Shell DDR4 AXI port.
//
// Timing knobs (seeded, so runs reproduce):
//   lat_min..lat_max  cycles from AR acceptance to the first R
//                     beat, and from the last W beat (with its AW)
//                     to the B response (>= 1)
//   rlat / blat       the same, separately for reads (AR -> first R)
//                     and writes (last W -> B); default = lat
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
// AW order; W beats may arrive before their AW. By default responses
// (R, B) come back in request order and a write is applied to memory
// as soon as its last W beat is in.
//
// Adversarial options (issue #73 F2 oops hunt; all off by default):
//   --axi-rw-race    the read and write channels are unordered, as
//                    AXI allows: a write becomes visible only when its
//                    B handshake completes (the latest point AXI
//                    permits), and a read samples memory at AR
//                    acceptance, so a read that overtakes an earlier,
//                    not yet acknowledged write to the same bytes gets
//                    the OLD data. Such reads are counted ("rw races").
//   --axi-ooo        responses to different IDs are reordered (and R
//                    beats of different IDs interleaved, AXI4 allows
//                    it): each cycle a random ID among those with a
//                    response ready is shown, held until taken.
//   --axi-early-b N  NON-COMPLIANT positive control: B is returned
//                    before the write is visible, which becomes
//                    visible only N cycles after the B handshake
//                    (an interconnect posting writes without read
//                    forwarding). A read of bytes covered by such an
//                    acknowledged-but-invisible write returns stale
//                    data and is counted ("stale reads"); used to show
//                    a test can detect a read-after-write ordering hole.
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
// Responses for one ID always come back in request order; the
// testbenches check the returned data against a reference.
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
  // Separate read / write-response latencies (-1: use lat_min/max).
  int rlat_min = -1, rlat_max = -1, blat_min = -1, blat_max = -1;
  bool rw_race = false;  // writes visible at B; reads may overtake them
  bool ooo = false;      // reorder responses across IDs
  int early_b = 0;       // non-compliant: write visible N cycles after B

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
    auto range = [&](int* lo, int* hi) {
      const char* s = argv[i + 1];
      const char* c = std::strchr(s, ':');
      *lo = std::atoi(s);
      *hi = c ? std::atoi(c + 1) : *lo;
      if (*lo < 1) *lo = 1;
      if (*hi < *lo) *hi = *lo;
    };
    if (std::strcmp(argv[i], "--axi-rlat") == 0 && need()) {
      range(&rlat_min, &rlat_max);
      return 2;
    }
    if (std::strcmp(argv[i], "--axi-blat") == 0 && need()) {
      range(&blat_min, &blat_max);
      return 2;
    }
    if (std::strcmp(argv[i], "--axi-rw-race") == 0) {
      rw_race = true;
      return 1;
    }
    if (std::strcmp(argv[i], "--axi-ooo") == 0) {
      ooo = true;
      return 1;
    }
    if (std::strcmp(argv[i], "--axi-early-b") == 0 && need()) {
      early_b = std::atoi(argv[i + 1]);
      if (early_b < 0) early_b = 0;
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
  int RlatMin() const { return rlat_min < 0 ? lat_min : rlat_min; }
  int RlatMax() const { return rlat_max < 0 ? lat_max : rlat_max; }
  int BlatMin() const { return blat_min < 0 ? lat_min : blat_min; }
  int BlatMax() const { return blat_max < 0 ? lat_max : blat_max; }
  std::string Describe() const {
    char b[320];
    std::snprintf(b, sizeof(b),
                  "axi lat R %d:%d B %d:%d gap %d ready aw/w/ar %d/%d/%d%% "
                  "seed %llu%s%s%s",
                  RlatMin(), RlatMax(), BlatMin(), BlatMax(), gap_max,
                  aw_ready, w_ready, ar_ready,
                  static_cast<unsigned long long>(seed),
                  rw_race ? " rw-race" : "", ooo ? " ooo" : "",
                  early_b ? (" EARLY-B " + std::to_string(early_b)).c_str() : "");
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
  // Called for every W beat as it is matched with its AW (whether or
  // not the write is visible yet): AXI byte address of the
  // data-width-aligned block, its bytes and byte strobes.
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
    // A response already shown stays selected until it is taken.
    if (b_sel_ < 0) b_sel_ = PickReady(bq_);
    if (b_sel_ >= 0) {
      const BResp& b = bq_.at(uint32_t(b_sel_)).front();
      s.bvalid = true;
      s.bid = b.id;
      s.bresp = b.resp;
    }
    if (r_sel_ < 0) r_sel_ = PickReady(rq_);
    if (r_sel_ >= 0) {
      const RBeat& r = rq_.at(uint32_t(r_sel_)).front();
      s.rvalid = true;
      s.rid = r.id;
      s.rresp = r.resp;
      s.rlast = r.last;
      std::memcpy(s.rdata, r.data, size_t(dw_));
    }
    // Slave-side self-check: a shown response stays until taken.
    if (last_.bvalid && !last_m_.bready &&
        (!s.bvalid || s.bid != last_.bid))
      Fail("BVALID dropped");
    if (last_.rvalid && !last_m_.rready &&
        (!s.rvalid || s.rid != last_.rid))
      Fail("RVALID dropped");
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
    // Writes that became visible (early-B mode) by this cycle.
    while (!delayed_.empty() && delayed_.front().visible_at <= now_) {
      Apply(delayed_.front());
      delayed_.pop_front();
    }
    // Responses retired this cycle.
    if (s.bvalid && m.bready) {
      auto& q = bq_[uint32_t(b_sel_)];
      BResp b = q.front();
      q.pop_front();
      if (q.empty()) bq_.erase(uint32_t(b_sel_));
      b_sel_ = -1;
      b_count_++;
      if (b.pw) {
        // Deferred write: visible now (rw-race) or later (early B).
        auto it = FindPending(b.seq);
        if (cfg_.early_b > 0) {
          it->visible_at = now_ + uint64_t(cfg_.early_b);
          delayed_.push_back(*it);
        } else {
          Apply(*it);
        }
        pending_.erase(it);
      }
    }
    if (s.rvalid && m.rready) {
      auto& q = rq_[uint32_t(r_sel_)];
      q.pop_front();
      r_beats_++;
      if (!q.empty() && q.front().ready_at <= now_ + 1) {
        q.front().ready_at = now_ + 1 + uint64_t(Rand(0, cfg_.gap_max));
      }
      if (q.empty()) rq_.erase(uint32_t(r_sel_));
      r_sel_ = -1;
    }
    // Requests.
    if (m.arvalid && s.arready) {
      CheckBurst("AR", m.araddr, m.arlen, m.arsize, m.arburst);
      ar_count_++;
      last_arprot_ = m.arprot;
      const uint64_t first =
          now_ + uint64_t(Rand(cfg_.RlatMin(), cfg_.RlatMax()));
      // Ordering hazards against writes not yet visible.
      const uint64_t lo = m.araddr & ~uint64_t(dw_ - 1);
      const uint64_t hi =
          BeatAddr(m.araddr, m.arsize, m.arlen) + (uint64_t(1) << m.arsize);
      for (const auto& p : pending_) {
        if (p.Overlaps(lo, hi)) {
          if (rw_race_++ < 10)
            std::fprintf(stderr,
                         "AXI model: rw race: AR 0x%llx overtakes the "
                         "unacknowledged write 0x%llx (AXI cycle %llu)\n",
                         U(m.araddr), U(p.lo), U(now_));
          break;
        }
      }
      for (const auto& p : delayed_) {
        if (p.Overlaps(lo, hi)) {
          if (stale_++ < 10)
            std::fprintf(stderr,
                         "AXI model: STALE READ: AR 0x%llx after the "
                         "acknowledged write 0x%llx is visible only at "
                         "AXI cycle %llu (now %llu)\n",
                         U(m.araddr), U(p.lo), U(p.visible_at), U(now_));
          break;
        }
      }
      // Beats queued behind earlier ones of the same ID; only the
      // first beat of this burst carries the latency, the rest the gap.
      auto& q = rq_[m.arid];
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
        q.push_back(b);
      }
      // Reads see memory as of acceptance (with the default and the
      // rw-race model, B is only sent once the write is visible).
    }
    if (m.awvalid && s.awready) {
      CheckBurst("AW", m.awaddr, m.awlen, m.awsize, m.awburst);
      Aw aw{m.awaddr, m.awid, m.awlen, m.awsize, 0};
      aw.seq = ++seq_;
      awq_.push_back(aw);
      aw_count_++;
      if (Deferred()) {
        // Pending from AW acceptance: a read may overtake it from now.
        PendW p;
        p.seq = aw.seq;
        p.lo = m.awaddr & ~uint64_t(dw_ - 1);
        p.hi = BeatAddr(m.awaddr, m.awsize, m.awlen) + (uint64_t(1) << m.awsize);
        pending_.push_back(p);
      }
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
    return rq_.empty() && bq_.empty() && awq_.empty() && wq_.empty() &&
           delayed_.empty();
  }
  uint8_t last_arprot() const { return last_arprot_; }
  uint64_t rw_races() const { return rw_race_; }
  uint64_t stale_reads() const { return stale_; }
  std::string Stats() const {
    char b[480];
    std::snprintf(b, sizeof(b),
        "AXI: %llu AR (%llu R beats), %llu AW (%llu W beats, %llu B); "
        "stall cycles AW %llu W %llu AR %llu R %llu B %llu; "
        "rw races %llu, stale reads %llu",
        U(ar_count_), U(r_beats_), U(aw_count_), U(w_beats_), U(b_count_),
        U(aw_stall_), U(w_stall_), U(ar_stall_), U(r_stall_), U(b_stall_),
        U(rw_race_), U(stale_));
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
    bool pw;       // a deferred write waits for this B
    uint64_t seq;
  };
  struct Aw {
    uint64_t addr;
    uint32_t id;
    uint8_t len, size;
    int beats_done;
    bool err = false;
    uint64_t seq = 0;
  };
  struct WBeat {
    uint8_t data[64];
    uint64_t strb;
    bool last;
  };
  struct PBeat {
    uint64_t blk;
    uint64_t strb;
    uint8_t data[64];
  };
  // A write not yet visible in memory (rw-race / early-B models).
  struct PendW {
    uint64_t seq = 0;
    uint64_t lo = 0, hi = 0;  // AXI byte range [lo, hi)
    uint64_t visible_at = 0;
    std::vector<PBeat> beats;
    bool Overlaps(uint64_t a, uint64_t b) const { return a < hi && lo < b; }
  };
  static unsigned long long U(uint64_t v) {
    return static_cast<unsigned long long>(v);
  }
  [[noreturn]] void Fail(const char* what) const {
    std::fprintf(stderr, "AXI PROTOCOL ERROR at AXI cycle %llu: %s\n",
                 U(now_), what);
    std::exit(4);
  }
  bool Deferred() const { return cfg_.rw_race || cfg_.early_b > 0; }
  std::deque<PendW>::iterator FindPending(uint64_t seq) {
    for (auto it = pending_.begin(); it != pending_.end(); ++it)
      if (it->seq == seq) return it;
    Fail("model: deferred write lost");
  }
  void Apply(const PendW& p) {
    for (const auto& b : p.beats)
      for (int k = 0; k < dw_; ++k)
        if (((b.strb >> k) & 1) && InMem(b.blk + k)) MemWrite(b.blk + k, b.data[k]);
  }
  // Random ID whose head response is ready (in-order mode: the ID of
  // the oldest ready head, i.e. the only queue for a one-ID master).
  template <typename Q>
  int PickReady(const std::map<uint32_t, Q>& qs) {
    int n = 0, pick = -1;
    for (const auto& [id, q] : qs) {
      if (q.empty() || q.front().ready_at > now_)
        continue;
      if (!cfg_.ooo) return int(id);
      if (Rand(0, n) == 0) pick = int(id);  // reservoir sampling
      n++;
    }
    return pick;
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
      PBeat pb{};
      pb.blk = blk;
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
          if (Deferred()) {
            pb.strb |= uint64_t(1) << k;
            pb.data[k] = w.data[k];
          } else {
            MemWrite(blk + k, w.data[k]);
          }
        } else {
          aw.err = true;
        }
      }
      if (Deferred()) FindPending(aw.seq)->beats.push_back(pb);
      if (obs_) obs_(blk, w.data, w.strb);
      if (++aw.beats_done > aw.len) {
        BResp r{aw.id, uint8_t(aw.err ? 3 : 0),
                now_ + uint64_t(Rand(cfg_.BlatMin(), cfg_.BlatMax())),
                Deferred(), aw.seq};
        bq_[aw.id].push_back(r);
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
  // Per-ID response queues (in order within an ID).
  std::map<uint32_t, std::deque<RBeat>> rq_;
  std::map<uint32_t, std::deque<BResp>> bq_;
  int r_sel_ = -1, b_sel_ = -1;
  std::deque<Aw> awq_;
  std::deque<WBeat> wq_;
  std::deque<PendW> pending_;  // accepted, not yet acknowledged
  std::deque<PendW> delayed_;  // acknowledged, not yet visible (early B)
  uint64_t seq_ = 0;
  AxiS cur_{}, last_{};
  AxiM last_m_{};
  uint8_t last_arprot_ = 0;
  uint64_t now_ = 0;
  uint64_t ar_count_ = 0, r_beats_ = 0, aw_count_ = 0, w_beats_ = 0;
  uint64_t b_count_ = 0;
  uint64_t aw_stall_ = 0, w_stall_ = 0, ar_stall_ = 0, r_stall_ = 0;
  uint64_t b_stall_ = 0;
  uint64_t rw_race_ = 0, stale_ = 0;
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
