// Streaming hash KATs through the muse_crypto_top AXI4-Lite registers
// (issue #6, docs/SPEC.md section 3): SHA-512, SHA3-256 and SHAKE256
// against Python hashlib, Keccak-256 against the in-repo sponge
// (sw/hash_kat.py, checked against published vectors). Lengths cover
// 0, rate-1, rate, rate+1, multi-rate and every 0..3-byte FIN tail.
// Also exercised: AXI write backpressure on a full buffer (writes
// issued back to back) vs. software polling HSTATUS.ready, HDOUT
// auto-increment and HOPTR random access, multi-block SHAKE squeeze,
// aborting a message with INIT while a block is in flight, error
// flags, and independence from the legacy SHA-256/field registers.
#include "Vmuse_crypto_top.h"
#include "hash_stream_kats.h"
#include "verilated.h"
#include "verilated_cov.h"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <vector>

namespace {

constexpr uint8_t kCtrl = 0x00, kStatus = 0x04, kDin = 0x08, kDout = 0x48;
constexpr uint8_t kHctrl = 0x8c, kHstatus = 0x90, kHdata = 0x94,
                  kHfin = 0x98, kHoptr = 0x9c, kHdout = 0xa0;
constexpr uint32_t kHsBusy = 1, kHsDone = 2, kHsReady = 4, kHsErr = 8;

std::vector<uint8_t> Bytes(const uint8_t* p, uint32_t n) {
  return std::vector<uint8_t>(p, p + n);
}

void PrintHex(const char* tag, const std::vector<uint8_t>& v) {
  std::printf("  %s=", tag);
  for (uint8_t b : v) std::printf("%02x", b);
  std::printf("\n");
}

}  // namespace

int main(int argc, char** argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  const std::unique_ptr<Vmuse_crypto_top> dut{
      new Vmuse_crypto_top{&context}};
  const char* cov_path = std::getenv("COV_FILE");
  uint64_t checks = 0, stall_cycles = 0, cycles = 0;

  auto tick = [&]() {
    dut->clk = 0;
    dut->eval();
    dut->clk = 1;
    dut->eval();
    dut->clk = 0;
    dut->eval();
    ++cycles;
  };

  dut->clk = 0;
  dut->rst_n = 0;
  dut->s_axi_awvalid = 0;
  dut->s_axi_wvalid = 0;
  dut->s_axi_bready = 0;
  dut->s_axi_arvalid = 0;
  dut->s_axi_rready = 0;
  tick();
  tick();
  dut->rst_n = 1;
  dut->eval();

  // AXI write; waits (bounded) for AWREADY, counting stall cycles.
  // `must_accept` fails the write if it is not taken immediately.
  auto wr = [&](uint8_t addr, uint32_t data, bool must_accept) -> bool {
    dut->s_axi_awaddr = addr;
    dut->s_axi_wdata = data;
    dut->s_axi_awvalid = 1;
    dut->s_axi_wvalid = 1;
    dut->eval();
    int waited = 0;
    while (!dut->s_axi_awready) {
      if (must_accept || ++waited > 200) {
        std::printf("FAIL wr %02x: AWREADY low (%d cycles)\n", addr, waited);
        return false;
      }
      tick();
      ++stall_cycles;
    }
    ++checks;
    if (!dut->s_axi_wready) {
      std::printf("FAIL wr %02x: WREADY low with AWREADY\n", addr);
      return false;
    }
    tick();
    dut->s_axi_awvalid = 0;
    dut->s_axi_wvalid = 0;
    dut->eval();
    ++checks;
    if (!dut->s_axi_bvalid || dut->s_axi_bresp != 0) {
      std::printf("FAIL wr %02x: no OKAY response\n", addr);
      return false;
    }
    dut->s_axi_bready = 1;
    tick();
    dut->s_axi_bready = 0;
    dut->eval();
    return true;
  };

  auto rd = [&](uint8_t addr, uint32_t* out) -> bool {
    dut->s_axi_araddr = addr;
    dut->s_axi_arvalid = 1;
    dut->eval();
    if (!dut->s_axi_arready) {
      std::printf("FAIL rd %02x: ARREADY low\n", addr);
      return false;
    }
    tick();
    dut->s_axi_arvalid = 0;
    dut->eval();
    ++checks;
    if (!dut->s_axi_rvalid || dut->s_axi_rresp != 0) {
      std::printf("FAIL rd %02x: no OKAY response\n", addr);
      return false;
    }
    *out = dut->s_axi_rdata;
    dut->s_axi_rready = 1;
    tick();
    dut->s_axi_rready = 0;
    dut->eval();
    return true;
  };

  auto wait_hs = [&](uint32_t mask, const char* what) -> bool {
    uint32_t st = 0;
    for (int i = 0; i < 2000; ++i) {
      if (!rd(kHstatus, &st)) return false;
      if (st & mask) return true;
    }
    std::printf("FAIL %s: HSTATUS=%08x never had %x\n", what, st, mask);
    return false;
  };

  auto read_out = [&](size_t nbytes, std::vector<uint8_t>* out) -> bool {
    for (size_t i = 0; i < nbytes; i += 4) {
      uint32_t w = 0;
      if (!rd(kHdout, &w)) return false;
      for (size_t b = 0; b < 4 && i + b < nbytes; ++b) {
        out->push_back(static_cast<uint8_t>(w >> (8 * b)));
      }
    }
    return true;
  };

  // Stream `msg` (already INITed). poll=true: software checks
  // HSTATUS.ready before each write, which must then be taken at once;
  // poll=false: writes are issued back to back and the slave stalls.
  // finish=false streams only whole words (len % 4 == 0), no FIN.
  auto stream = [&](const uint8_t* msg, uint32_t len, bool poll,
                    bool finish = true) -> bool {
    const uint32_t full = len / 4;
    for (uint32_t i = 0; i < full + (finish ? 1u : 0u); ++i) {
      uint32_t w = 0;
      const uint32_t nb = (i < full) ? 4 : len % 4;
      for (uint32_t b = 0; b < nb; ++b) {
        w |= static_cast<uint32_t>(msg[4 * i + b]) << (8 * b);
      }
      if (poll && !wait_hs(kHsReady, "HSTATUS.ready")) return false;
      if (i < full) {
        if (!wr(kHdata, w, poll)) return false;
      } else if (!wr(kHfin, (nb << 24) | w, poll)) {
        return false;
      }
    }
    return true;
  };

  // Full hash: INIT, stream, wait, read (with SHAKE squeezes).
  auto hash = [&](int mode, const uint8_t* msg, uint32_t len,
                  uint32_t outlen, bool poll,
                  std::vector<uint8_t>* out) -> bool {
    out->clear();
    if (!wr(kHctrl, static_cast<uint32_t>(mode << 4) | 1u, true)) {
      return false;
    }
    if (!stream(msg, len, poll) || !wait_hs(kHsDone, "hash done")) {
      return false;
    }
    const uint32_t rate = (mode == 0) ? 64 : 136;  // readable bytes
    while (true) {
      const uint32_t take = std::min(rate, outlen - (uint32_t)out->size());
      if (!read_out(take, out)) return false;
      if (out->size() >= outlen) return true;
      if (!wr(kHctrl, 0x2, true)) return false;  // SQUEEZE
      if (!wait_hs(kHsDone, "squeeze done")) return false;
    }
  };

  auto check = [&](bool ok, const char* what) -> bool {
    ++checks;
    if (!ok) std::printf("FAIL %s\n", what);
    return ok;
  };

  uint32_t v = 0;
  // Data before any INIT is ignored and flags an error.
  if (!rd(kHstatus, &v) || !check(v == 0, "HSTATUS idle after reset") ||
      !wr(kHdata, 0x12345678u, true) || !rd(kHstatus, &v) ||
      !check((v & kHsErr) != 0, "HDATA before INIT sets err")) {
    return 1;
  }

  int npass = 0;
  int per_mode[4] = {0, 0, 0, 0};
  for (int k = 0; k < kNumHashKats; ++k) {
    const HashKat& t = kHashKats[k];
    std::vector<uint8_t> got;
    const bool poll = (k % 2) == 1;
    if (!hash(t.mode, t.msg, t.len, t.outlen, poll, &got)) {
      std::printf("FAIL %s len=%u: protocol\n", t.name, t.len);
      return 1;
    }
    ++checks;
    if (got != Bytes(t.out, t.outlen)) {
      std::printf("FAIL %s len=%u outlen=%u (%s)\n", t.name, t.len,
                  t.outlen, poll ? "poll" : "backpressure");
      PrintHex("got", got);
      PrintHex("exp", Bytes(t.out, t.outlen));
      return 1;
    }
    if (!rd(kHstatus, &v) || !check((v & kHsErr) == 0, "no err after KAT")) {
      return 1;
    }
    std::printf("PASS %-9s len=%4u out=%3u %s\n", t.name, t.len, t.outlen,
                poll ? "poll" : "backpressure");
    ++npass;
    ++per_mode[t.mode];
  }
  if (!check(stall_cycles > 0, "back-to-back writes saw AXI backpressure")) {
    return 1;
  }

  // HCTRL mode readback, HOPTR random access, squeeze in SHA mode = err.
  {
    const HashKat* sha = nullptr;
    for (int k = 0; k < kNumHashKats; ++k) {
      if (kHashKats[k].mode == 0 && kHashKats[k].len == 1000) {
        sha = &kHashKats[k];
      }
    }
    std::vector<uint8_t> got;
    if (!check(sha != nullptr, "sha512 len 1000 vector present") ||
        !hash(0, sha->msg, sha->len, 64, false, &got) ||
        !rd(kHctrl, &v) || !check(((v >> 4) & 3) == 0, "HCTRL mode=0") ||
        !wr(kHoptr, 5, true) || !rd(kHoptr, &v) ||
        !check(v == 5, "HOPTR readback") || !rd(kHdout, &v)) {
      return 1;
    }
    const uint32_t want = sha->out[20] | (sha->out[21] << 8) |
                          (sha->out[22] << 16) |
                          (static_cast<uint32_t>(sha->out[23]) << 24);
    if (!check(v == want, "HDOUT[5] via HOPTR") || !rd(kHoptr, &v) ||
        !check(v == 6, "HDOUT auto-increment") ||
        !wr(kHctrl, 0x2, true) || !rd(kHstatus, &v) ||
        !check((v & (kHsErr | kHsDone)) == (kHsErr | kHsDone),
               "SQUEEZE in SHA-512 mode: err, digest kept")) {
      return 1;
    }
    std::printf("PASS HOPTR/HDOUT/HCTRL/err registers\n");
  }

  // Abort: INIT while a SHA-512 block is in flight, then a fresh
  // Keccak-256 message, then a SHA-512 message must still be right.
  {
    const HashKat* kec = nullptr;
    const HashKat* sha = nullptr;
    for (int k = 0; k < kNumHashKats; ++k) {
      if (kHashKats[k].mode == 2 && kHashKats[k].len == 273) {
        kec = &kHashKats[k];
      }
      if (kHashKats[k].mode == 0 && kHashKats[k].len == 257) {
        sha = &kHashKats[k];
      }
    }
    if (!check(kec && sha, "abort vectors present")) return 1;
    if (!wr(kHctrl, 0x01, true)) return 1;
    for (int i = 0; i < 40; ++i) {  // one block issued, 8 words buffered
      if (!wr(kHdata, 0xdeadbeefu ^ i, false)) return 1;
    }
    if (!rd(kHstatus, &v) || !check((v & kHsBusy) != 0, "busy mid-block")) {
      return 1;
    }
    std::vector<uint8_t> got;
    if (!hash(2, kec->msg, kec->len, 32, false, &got) ||
        !check(got == Bytes(kec->out, 32), "keccak256 after abort") ||
        !wr(kHctrl, 0x01, true) || !wr(kHdata, 1, false) ||
        !hash(0, sha->msg, sha->len, 64, false, &got) ||
        !check(got == Bytes(sha->out, 64), "sha512 after abort")) {
      return 1;
    }
    std::printf("PASS INIT aborts an in-flight message\n");
  }

  // Legacy engines run while a hash message is half streamed; the
  // legacy STATUS does not reflect hash activity and vice versa.
  {
    const HashKat* sha = nullptr;
    for (int k = 0; k < kNumHashKats; ++k) {
      if (kHashKats[k].mode == 0 && kHashKats[k].len == 1000) {
        sha = &kHashKats[k];
      }
    }
    if (!wr(kHctrl, 0x01, true) || !stream(sha->msg, 500, false, false)) {
      return 1;
    }
    // SHA-256("abc") single block via DIN/CTRL.
    if (!wr(kDin, 0x61626380u, true)) return 1;
    for (int i = 1; i < 15; ++i) {
      if (!wr(static_cast<uint8_t>(kDin + 4 * i), 0, true)) return 1;
    }
    if (!wr(kDin + 60, 24, true) || !wr(kCtrl, 1, true)) return 1;
    v = 0;
    for (int i = 0; i < 200 && (v & 2) == 0; ++i) {
      if (!rd(kStatus, &v)) return 1;
    }
    uint32_t d0 = 0, d7 = 0;
    if (!check((v & 2) != 0, "legacy SHA-256 done") || !rd(kDout, &d0) ||
        !rd(kDout + 28, &d7) ||
        !check(d0 == 0xf20015adu && d7 == 0xba7816bfu,
               "legacy SHA-256(abc) mid-stream")) {
      return 1;
    }
    // Finish the SHA-512 message: bytes 500..999.
    std::vector<uint8_t> got;
    if (!stream(sha->msg + 500, 500, true) ||
        !wait_hs(kHsDone, "sha512 split") || !read_out(64, &got) ||
        !check(got == Bytes(sha->out, 64),
               "sha512(1000) with legacy op interleaved")) {
      return 1;
    }
    if (!rd(kStatus, &v) || !check((v & 1) == 0, "legacy STATUS idle")) {
      return 1;
    }
    std::printf("PASS legacy SHA-256 interleaved with a stream\n");
  }

  dut->final();
  if (cov_path != nullptr) context.coveragep()->write(cov_path);
  std::printf(
      "TB_HASH_STREAM PASS (%d KATs: sha512=%d sha3_256=%d keccak256=%d "
      "shake256=%d; %llu checks, %llu backpressure cycles, %llu cycles)\n",
      npass, per_mode[0], per_mode[1], per_mode[2], per_mode[3],
      static_cast<unsigned long long>(checks),
      static_cast<unsigned long long>(stall_cycles),
      static_cast<unsigned long long>(cycles));
  return 0;
}
