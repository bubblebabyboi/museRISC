# Bulk hashing of a 64 KiB buffer

This is the throughput half of issue
[#10](https://github.com/bubblebabyboi/sigil/issues/10). It shares its
implementations, known-answer tests and `gen_kat.py` with
[`sha256chain`](../sha256chain/README.md), which documents both
benchmarks.

| Region | Work |
|---|---|
| 0 | SHA-256 of the buffer, plain C |
| 1 | SHA-256 of the buffer, C + Zknh |
| 2 | SHA-256 of 16 equal segments (4 KiB each at 64 KiB), RVV ×16 multi-buffer |
| 3 | SHA-512 of the buffer, accelerator streaming engine (`sigil_hash()`) |
| 4 | SHA3-256 of the buffer, accelerator streaming engine (`sigil_hash()`) |

- `iterations` is the buffer size in KiB (64 by default), with
  `bytes_per_iteration` 1024. The harness's bytes/cycle is therefore the
  size of the buffer divided by the cycles of the region.
- There is no SHA-256 accelerator region. The SHA-256 engine hashes one
  block from the IV with no chaining, so it cannot hash a multi-block
  message.

```sh
make -C sim perf BENCHES=sha256chain_bulk
make -C sw/bench/sha256chain_bulk run
```
