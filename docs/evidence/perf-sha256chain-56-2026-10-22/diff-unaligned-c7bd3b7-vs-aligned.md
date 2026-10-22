# Sigil performance diff

- A: `c7bd3b7d8dfe` 2026-10-22T09:58:49Z
- B: `2b8e1aebfb15` 2026-10-22T09:55:45Z

Runs in only one set: sha256chain[sdk] sha256 plain C default/axi (B), sha256chain[sdk] sha256 Zknh default/axi (B), sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/axi (B), sha256chain[sdk] sha256 accel sigil_sha256_block default/axi (B), sha256chain[sdk] sha256 accel sigil_sha256 default/axi (B), sha256chain[sdk] sha512 accel sigil_hash default/axi (B), sha256chain[sdk] sha3-256 accel sigil_hash default/axi (B), sha256chain_bulk[sdk] sha256 plain C default/axi (B), sha256chain_bulk[sdk] sha256 Zknh default/axi (B), sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/axi (B), sha256chain_bulk[sdk] sha512 accel sigil_hash default/axi (B), sha256chain_bulk[sdk] sha3-256 accel sigil_hash default/axi (B)

| Run | Cycles A | Cycles B | Change | IPC A | IPC B | Metric A | Metric B |
|---|---:|---:|---:|---:|---:|---|---|
| sha256chain[sdk] sha256 plain C default/soc | 10,208,495 | 10,156,268 | -0.51% | 0.364 | 0.366 | - | - |
| sha256chain[sdk] sha256 Zknh default/soc | 7,385,318 | 6,915,325 | -6.36% | 0.370 | 0.395 | - | - |
| sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/soc | 4,753,409 | 4,753,403 | -0.00% | 0.046 | 0.046 | - | - |
| sha256chain[sdk] sha256 accel sigil_sha256_block default/soc | 602,189 | 585,822 | -2.72% | 0.270 | 0.278 | - | - |
| sha256chain[sdk] sha256 accel sigil_sha256 default/soc | 2,876,530 | 2,860,176 | -0.57% | 0.358 | 0.360 | - | - |
| sha256chain[sdk] sha512 accel sigil_hash default/soc | 3,609,723 | 2,531,505 | -29.87% | 0.280 | 0.400 | - | - |
| sha256chain[sdk] sha3-256 accel sigil_hash default/soc | 1,920,058 | 1,403,005 | -26.93% | 0.287 | 0.396 | - | - |
| sha256chain_bulk[sdk] sha256 plain C default/soc | 10,115,438 | 10,114,258 | -0.01% | 0.366 | 0.366 | 0.0065 B/cycle | 0.0065 B/cycle |
| sha256chain_bulk[sdk] sha256 Zknh default/soc | 6,903,364 | 6,903,194 | -0.00% | 0.396 | 0.396 | 0.0095 B/cycle | 0.0095 B/cycle |
| sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/soc | 5,509,491 | 4,996,705 | -9.31% | 0.041 | 0.045 | 0.0119 B/cycle | 0.0131 B/cycle |
| sha256chain_bulk[sdk] sha512 accel sigil_hash default/soc | 275,406 | 274,480 | -0.34% | 0.241 | 0.242 | 0.2380 B/cycle | 0.2388 B/cycle |
| sha256chain_bulk[sdk] sha3-256 accel sigil_hash default/soc | 274,201 | 273,326 | -0.32% | 0.241 | 0.242 | 0.2390 B/cycle | 0.2398 B/cycle |

## Accounting categories that moved (cycles B - A, and share of A's cycles)

- sha256chain[sdk] sha256 plain C default/soc: fetch: I$ hit latency / issue gap -45,057 (-0.4 pp), fetch: 32-bit instr straddles a word -6,149 (-0.1 pp), fetch: I$ miss +1 (+0.0 pp), squashed: jal -1,022 (-0.0 pp)
- sha256chain[sdk] sha256 Zknh default/soc: retire (base) +2 (+0.0 pp), fetch: I$ hit latency / issue gap -190,454 (-2.6 pp), fetch: 32-bit instr straddles a word -350,199 (-4.7 pp), fetch: I$ miss +2 (+0.0 pp), squashed: taken branch +71,680 (+1.0 pp), squashed: jal -1,025 (-0.0 pp), squashed: jalr +1 (+0.0 pp)
- sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/soc: retire (base) -1 (-0.0 pp), fetch: I$ hit latency / issue gap +1 (+0.0 pp), fetch: 32-bit instr straddles a word -8 (-0.0 pp), fetch: I$ miss +1 (+0.0 pp), squashed: jal +1 (+0.0 pp)
- sha256chain[sdk] sha256 accel sigil_sha256_block default/soc: retire (base) +12 (+0.0 pp), fetch: I$ hit latency / issue gap +14,345 (+2.4 pp), fetch: 32-bit instr straddles a word -25,600 (-4.3 pp), fetch: I$ miss -11 (-0.0 pp), squashed: taken branch -4,097 (-0.7 pp), squashed: jal +1 (+0.0 pp), squashed: jalr -1,023 (-0.2 pp), MEM: D$ hit latency +6 (+0.0 pp)
- sha256chain[sdk] sha256 accel sigil_sha256 default/soc: retire (base) +15 (+0.0 pp), fetch: I$ hit latency / issue gap +14,345 (+0.5 pp), fetch: 32-bit instr straddles a word -25,602 (-0.9 pp), fetch: I$ miss -2 (-0.0 pp), squashed: taken branch -4,096 (-0.1 pp), squashed: jal +1 (+0.0 pp), squashed: jalr -1,023 (-0.0 pp), MEM: D$ hit latency +8 (+0.0 pp)
- sha256chain[sdk] sha512 accel sigil_hash default/soc: retire (base) +1,049 (+0.0 pp), fetch: I$ hit latency / issue gap -521,195 (-14.4 pp), fetch: 32-bit instr straddles a word -574,460 (-15.9 pp), fetch: I$ miss -13 (-0.0 pp), squashed: taken branch +20,479 (+0.6 pp), squashed: jal +1 (+0.0 pp), squashed: jalr +1,024 (+0.0 pp), MEM: D$ hit latency -1,011 (-0.0 pp), MEM: uncached device access -4,092 (-0.1 pp)
- sha256chain[sdk] sha3-256 accel sigil_hash default/soc: retire (base) +4,118 (+0.2 pp), fetch: I$ hit latency / issue gap -251,886 (-13.1 pp), fetch: 32-bit instr straddles a word -278,525 (-14.5 pp), fetch: I$ miss +12 (+0.0 pp), squashed: taken branch +8,191 (+0.4 pp), squashed: jal +1 (+0.0 pp), squashed: jalr +1,024 (+0.1 pp), MEM: D$ hit latency +12 (+0.0 pp)
- sha256chain_bulk[sdk] sha256 plain C default/soc: retire (base) +1 (+0.0 pp), fetch: I$ hit latency / issue gap -10 (-0.0 pp), fetch: 32-bit instr straddles a word -16 (-0.0 pp), fetch: I$ miss -41 (-0.0 pp), squashed: taken branch +1 (+0.0 pp), squashed: jal +1 (+0.0 pp), MEM: D$ miss -1,116 (-0.0 pp)
- sha256chain_bulk[sdk] sha256 Zknh default/soc: fetch: I$ hit latency / issue gap -13 (-0.0 pp), fetch: 32-bit instr straddles a word -14 (-0.0 pp), fetch: I$ miss +4 (+0.0 pp), squashed: taken branch -1 (-0.0 pp), squashed: jal +1 (+0.0 pp), MEM: D$ miss -147 (-0.0 pp)
- sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/soc: retire (base) -3 (-0.0 pp), fetch: I$ hit latency / issue gap -291,018 (-5.3 pp), fetch: 32-bit instr straddles a word -221,354 (-4.0 pp), fetch: I$ miss -530 (-0.0 pp), squashed: taken branch +65 (+0.0 pp), squashed: jal +195 (+0.0 pp), load-use interlock -65 (-0.0 pp), EX: vector unit +65 (+0.0 pp), MEM: vector load/store -141 (-0.0 pp)
- sha256chain_bulk[sdk] sha512 accel sigil_hash default/soc: retire (base) -7 (-0.0 pp), fetch: I$ hit latency / issue gap +15,859 (+5.8 pp), fetch: 32-bit instr straddles a word -16,922 (-6.1 pp), fetch: I$ miss -32 (-0.0 pp), squashed: taken branch +20 (+0.0 pp), squashed: jal -1 (-0.0 pp), squashed: jalr +1 (+0.0 pp), MEM: D$ hit latency +1 (+0.0 pp), MEM: D$ miss +151 (+0.1 pp), MEM: uncached device access +4 (+0.0 pp)
- sha256chain_bulk[sdk] sha3-256 accel sigil_hash default/soc: retire (base) -10 (-0.0 pp), fetch: I$ hit latency / issue gap +16,105 (+5.9 pp), fetch: 32-bit instr straddles a word -16,660 (-6.1 pp), fetch: I$ miss +1 (+0.0 pp), squashed: taken branch +7 (+0.0 pp), squashed: jalr +1 (+0.0 pp), MEM: D$ miss -319 (-0.1 pp)

