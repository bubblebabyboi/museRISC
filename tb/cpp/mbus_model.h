// Memory-bus slave model for the museRISC "mbus" master port
// (protocol: rtl/core/muserisc_cpu.sv header). Used by core_tb,
// soc_tb and the cache unit testbenches.
//
// Timing knobs (randomized from a seed, so runs reproduce):
//   lat_min..lat_max  cycles from the request beat that completes
//                     a request to its first response beat (>= 1)
//   gap_max           extra idle cycles inserted between the
//                     beats of a read burst (0..gap_max each)
//   ready_pct         probability (0..100) that req_ready is high
//                     in a given cycle (backpressure)
// The model owns no storage: reads and writes go through the
// Read/Write callbacks, so harnesses keep their own memory maps
// and device side effects. A read's data is fetched when the
// request is accepted (one transaction at a time on this bus,
// so this is indistinguishable from fetching it later).
#ifndef MUSERISC_MBUS_MODEL_H_
#define MUSERISC_MBUS_MODEL_H_

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <functional>
#include <random>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

struct MbusConfig {
  int lat_min = 1;
  int lat_max = 1;
  int gap_max = 0;
  int ready_pct = 100;
  uint64_t seed = 1;

  // Parses "--mem-lat A:B", "--mem-gap N", "--mem-ready P",
  // "--mem-seed S". Returns the number of argv slots consumed
  // (0 if argv[i] is not a bus option).
  int Parse(int argc, char** argv, int i) {
    auto need = [&]() { return i + 1 < argc; };
    if (std::strcmp(argv[i], "--mem-lat") == 0 && need()) {
      const char* s = argv[i + 1];
      const char* c = std::strchr(s, ':');
      lat_min = std::atoi(s);
      lat_max = c ? std::atoi(c + 1) : lat_min;
      if (lat_min < 1) lat_min = 1;
      if (lat_max < lat_min) lat_max = lat_min;
      return 2;
    }
    if (std::strcmp(argv[i], "--mem-gap") == 0 && need()) {
      gap_max = std::atoi(argv[i + 1]);
      return 2;
    }
    if (std::strcmp(argv[i], "--mem-ready") == 0 && need()) {
      ready_pct = std::atoi(argv[i + 1]);
      if (ready_pct < 1) ready_pct = 1;
      if (ready_pct > 100) ready_pct = 100;
      return 2;
    }
    if (std::strcmp(argv[i], "--mem-seed") == 0 && need()) {
      seed = std::strtoull(argv[i + 1], nullptr, 0);
      return 2;
    }
    return 0;
  }
  std::string Describe() const {
    char b[128];
    std::snprintf(b, sizeof(b), "lat %d:%d gap %d ready %d%% seed %llu",
                  lat_min, lat_max, gap_max, ready_pct,
                  static_cast<unsigned long long>(seed));
    return b;
  }
};

class MbusModel {
 public:
  using ReadFn = std::function<uint64_t(uint64_t addr, uint8_t be,
                                        bool inst, bool burst)>;
  using WriteFn = std::function<void(uint64_t addr, uint8_t be,
                                     uint64_t wdata)>;

  MbusModel(const MbusConfig& cfg, ReadFn rd, WriteFn wr)
      : cfg_(cfg), rng_(cfg.seed), rd_(std::move(rd)), wr_(std::move(wr)) {}

  // Clock-low phase: the slave-driven signals for this cycle.
  struct Drive {
    bool req_ready, rsp_valid, rsp_last;
    uint64_t rsp_rdata;
  };
  Drive Outputs() {
    Drive d{};
    d.req_ready = Roll(cfg_.ready_pct);
    if (!q_.empty() && q_.front().ready_at <= now_) {
      const Txn& t = q_.front();
      d.rsp_valid = true;
      d.rsp_rdata = t.data[t.idx];
      d.rsp_last = (t.idx + 1 == t.data.size());
    }
    last_ = d;
    return d;
  }

  // Rising edge: apply the request beat (if it fired) and retire
  // the response beat driven this cycle.
  struct Req {
    bool valid, fire, write, last, inst;
    uint64_t addr, wdata;
    uint8_t be, len;
  };
  // Request-channel protocol check, every cycle: a beat offered
  // with valid && !ready must be offered again next cycle with
  // the identical payload (AXI-style stability). A violation is
  // fatal (exit 4) so no harness can miss it.
  void CheckStable(const Req& r) {
    if (offer_pending_) {
      const Req& p = offer_;
      if (!r.valid || r.addr != p.addr || r.write != p.write ||
          r.len != p.len || r.be != p.be || r.last != p.last ||
          r.inst != p.inst || r.wdata != p.wdata) {
        std::fprintf(stderr,
            "MBUS PROTOCOL ERROR at bus cycle %llu: offered beat changed "
            "before acceptance (valid %d->%d addr 0x%llx->0x%llx inst %d->%d "
            "write %d->%d len %u->%u be 0x%02x->0x%02x wdata 0x%llx->0x%llx)\n",
            static_cast<unsigned long long>(now_), p.valid, r.valid,
            static_cast<unsigned long long>(p.addr),
            static_cast<unsigned long long>(r.addr), p.inst, r.inst,
            p.write, r.write, p.len, r.len, p.be, r.be,
            static_cast<unsigned long long>(p.wdata),
            static_cast<unsigned long long>(r.wdata));
        std::exit(4);
      }
    }
    offer_pending_ = r.valid && !r.fire;
    offer_ = r;
  }
  void Edge(const Req& r) {
    CheckStable(r);
    if (last_.rsp_valid) {
      Txn& t = q_.front();
      if (++t.idx == t.data.size()) {
        q_.pop_front();
      } else {
        t.ready_at = now_ + 1 + Rand(0, cfg_.gap_max);
      }
    }
    if (r.fire) {
      if (r.write) {
        // Burst beats carry their own addresses.
        wr_(r.addr, r.be, r.wdata);
        writes_++;
        if (r.last) Push(std::vector<uint64_t>(1, 0));  // write ack
      } else {
        std::vector<uint64_t> data(size_t(r.len) + 1);
        for (size_t i = 0; i < data.size(); ++i) {
          data[i] = rd_(r.addr + 8 * i, r.be, r.inst, r.len != 0);
        }
        reads_ += r.len != 0 ? 0 : 1;
        bursts_ += r.len != 0 ? 1 : 0;
        Push(std::move(data));
      }
    }
    now_++;
  }

  bool Idle() const { return q_.empty(); }
  uint64_t reads() const { return reads_; }
  uint64_t bursts() const { return bursts_; }
  uint64_t writes() const { return writes_; }

 private:
  struct Txn {
    std::vector<uint64_t> data;
    size_t idx = 0;
    uint64_t ready_at = 0;
  };
  void Push(std::vector<uint64_t> data) {
    Txn t;
    t.data = std::move(data);
    // The first beat comes no earlier than the next cycle.
    t.ready_at = now_ + uint64_t(Rand(cfg_.lat_min, cfg_.lat_max));
    q_.push_back(std::move(t));
  }
  bool Roll(int pct) {
    if (pct >= 100) return true;
    return int(rng_() % 100) < pct;
  }
  int Rand(int lo, int hi) {
    if (hi <= lo) return lo;
    return lo + int(rng_() % uint64_t(hi - lo + 1));
  }

  MbusConfig cfg_;
  std::mt19937_64 rng_;
  ReadFn rd_;
  WriteFn wr_;
  std::deque<Txn> q_;
  Drive last_{};
  bool offer_pending_ = false;
  Req offer_{};
  uint64_t now_ = 0, reads_ = 0, bursts_ = 0, writes_ = 0;
};

namespace mbus_detail {
template <typename T, typename = void>
struct HasWrite : std::false_type {};
template <typename T>
struct HasWrite<T, std::void_t<decltype(std::declval<T&>().bus_req_write_o)>>
    : std::true_type {};
template <typename T, typename = void>
struct HasInst : std::false_type {};
template <typename T>
struct HasInst<T, std::void_t<decltype(std::declval<T&>().bus_req_inst_o)>>
    : std::true_type {};
}  // namespace mbus_detail

// Wires an MbusModel to a Verilated top with the muserisc_cpu
// bus port names: MbusDrive() before the clock-low eval,
// MbusSample() after it (before the rising edge), then
// MbusModel::Edge() with the sample after the rising-edge eval.
template <typename Top>
void MbusDrive(MbusModel* m, Top* dut) {
  const auto d = m->Outputs();
  dut->bus_req_ready_i = d.req_ready;
  dut->bus_rsp_valid_i = d.rsp_valid;
  dut->bus_rsp_rdata_i = d.rsp_rdata;
  dut->bus_rsp_last_i = d.rsp_last;
}
template <typename Top>
MbusModel::Req MbusSample(Top* dut) {
  MbusModel::Req r{};
  r.valid = dut->bus_req_valid_o;
  r.fire = r.valid && dut->bus_req_ready_i;
  r.addr = dut->bus_req_addr_o;
  r.be = dut->bus_req_be_o;
  r.len = dut->bus_req_len_o;
  r.last = true;
  // Read-only masters (the I$ alone) have no write channel; a
  // master without req_inst is a data master.
  if constexpr (mbus_detail::HasWrite<Top>::value) {
    r.write = dut->bus_req_write_o;
    r.last = dut->bus_req_last_o;
    r.wdata = dut->bus_req_wdata_o;
  }
  if constexpr (mbus_detail::HasInst<Top>::value) {
    r.inst = dut->bus_req_inst_o;
  } else {
    r.inst = !mbus_detail::HasWrite<Top>::value;
  }
  return r;
}

#endif  // MUSERISC_MBUS_MODEL_H_
