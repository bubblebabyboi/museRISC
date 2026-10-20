// museRISC streaming hash engine (issue #6): arbitrary-length
// SHA-512 (FIPS 180-4) and Keccak sponge hashing at rate 1088
// (SHA3-256, Keccak-256, SHAKE256; FIPS 202) behind the
// muse_crypto_top register window (docs/SPEC.md, sw/muse_crypto.h).
//
// Software streams the message as 32-bit words (first message byte
// in bits [7:0]) and ends it with one FIN word carrying the 0..3
// trailing bytes. The engine buffers one rate block, padding and the
// SHA-512 length field are added in hardware, and full blocks are
// handed to sha512_block / keccak_f1600, which latch their input on
// start; so the buffer refills while the previous block is still
// being compressed. `in_ready` drops only while the buffer is full
// and the core is still busy; muse_crypto_top turns that into AXI
// write backpressure.
//
// Modes: 0 SHA-512 (rate 128 B), 1 SHA3-256 (domain 0x06),
// 2 Keccak-256 (0x01), 3 SHAKE256 (0x1F); Keccak modes rate 136 B.
// Output (valid while `done`): out_word(i) is digest/rate-output
// word i, bytes in output order with the first byte in bits [7:0].
// SHA-512: words 0..15. Keccak modes: words 0..33 (the full rate);
// a squeeze command permutes again for further SHAKE output.
`default_nettype none
module muse_hash_stream (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        init,       // start a new message in `init_mode`
    input  wire [1:0]  init_mode,
    input  wire        squeeze,    // Keccak modes, while done
    input  wire        data_we,    // append 4 message bytes
    input  wire        fin_we,     // append fin_cnt bytes, then pad
    input  wire [31:0] wdata,      // data word, or FIN {cnt[25:24], bytes[23:0]}
    output logic       in_ready,   // data_we / fin_we would be taken now
    output logic       stall,      // absorbing but buffer full (wait)
    output logic       busy,
    output logic       done,
    output logic       err,        // data/FIN/squeeze outside its phase
    output logic [1:0] mode,
    input  wire [5:0]  out_idx,
    output logic [31:0] out_word
);
  localparam logic [1:0] M_SHA512 = 2'd0;
  localparam logic [1:0] M_SHA3   = 2'd1;
  localparam logic [1:0] M_KEC256 = 2'd2;

  typedef enum logic [2:0] {
    S_IDLE, S_ABSORB, S_FIN, S_FIN_LEN, S_WAIT, S_DONE, S_SQZ
  } state_t;
  state_t state;

  logic [31:0] bufw [34];
  logic [5:0]  wcount;     // words in bufw
  logic [5:0]  wpad;       // word index holding the first pad byte
  logic [63:0] nbytes;     // message length so far
  logic        first;      // next block is the first of the message
  logic        inflight;   // a core run was started and is not done

  logic        is_sha;
  logic [5:0]  rate_w;
  assign is_sha = (mode == M_SHA512);
  assign rate_w = is_sha ? 6'd32 : 6'd34;

  function automatic logic [31:0] bswap(input logic [31:0] x);
    bswap = {x[7:0], x[15:8], x[23:16], x[31:24]};
  endfunction

  // Block views of the buffer.
  logic [1023:0] sha_blk;
  logic [1087:0] kec_blk;
  always_comb begin
    for (int i = 0; i < 32; i++) begin
      sha_blk[1023 - 32 * i -: 32] = bswap(bufw[i]);
    end
    for (int i = 0; i < 34; i++) begin
      kec_blk[32 * i +: 32] = bufw[i];
    end
  end

  // A full buffer is issued as soon as the core is free (never in
  // S_FIN, which still edits the last block).
  logic go, sqz_go;
  assign go = (wcount == rate_w) && !inflight && (state != S_FIN);
  assign sqz_go = squeeze && !init && (state == S_DONE) && !is_sha;

  logic          sha_start, sha_busy, sha_done;
  logic [511:0]  sha_digest;
  logic          kec_start, kec_busy, kec_done;
  logic [1599:0] kec_in, kec_out;
  assign sha_start = go && is_sha;
  assign kec_start = (go && !is_sha) || sqz_go;
  assign kec_in = sqz_go ? kec_out
                         : ((first ? 1600'b0 : kec_out) ^
                            {512'b0, kec_blk});

  sha512_block u_sha512 (
      .clk(clk), .rst_n(rst_n), .start(sha_start), .cont(!first),
      .block_in(sha_blk), .digest_out(sha_digest),
      .busy(sha_busy), .done(sha_done));
  keccak_f1600 u_keccak (
      .clk(clk), .rst_n(rst_n), .start(kec_start),
      .state_in(kec_in), .state_out(kec_out),
      .busy(kec_busy), .done(kec_done));

  // FIN word: trailing bytes, then the first pad byte.
  logic [1:0]  fin_cnt;
  logic [7:0]  pad_byte;
  logic [31:0] fin_mask, fin_word;
  assign fin_cnt = wdata[25:24];
  always_comb begin
    case (mode)
      M_SHA512: pad_byte = 8'h80;
      M_SHA3:   pad_byte = 8'h06;
      M_KEC256: pad_byte = 8'h01;
      default:  pad_byte = 8'h1f;
    endcase
    fin_mask = (32'h1 << {fin_cnt, 3'b000}) - 32'h1;
    fin_word = (wdata & fin_mask) |
               ({24'b0, pad_byte} << {fin_cnt, 3'b000});
  end

  // SHA-512 128-bit big-endian bit length, as four buffer words.
  logic [127:0] bitlen;
  assign bitlen = {61'b0, nbytes, 3'b000};

  assign stall    = (state == S_ABSORB) && (wcount >= rate_w);
  assign in_ready = (state == S_ABSORB) && (wcount < rate_w);
  assign busy     = inflight || (state == S_FIN) ||
                    (state == S_FIN_LEN) || (state == S_WAIT) ||
                    (state == S_SQZ);
  assign done     = (state == S_DONE);

  always_comb begin
    out_word = '0;
    if (state == S_DONE) begin
      if (is_sha) begin
        if (out_idx < 6'd16) begin
          out_word = bswap(sha_digest[511 - 32 * out_idx[3:0] -: 32]);
        end
      end else if (out_idx < 6'd34) begin
        out_word = kec_out[32 * out_idx +: 32];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE; mode <= M_SHA512; err <= 1'b0;
      wcount <= '0; wpad <= '0; nbytes <= '0;
      first <= 1'b1; inflight <= 1'b0;
      for (int i = 0; i < 34; i++) bufw[i] <= '0;
    end else begin
      if (sha_done || kec_done) inflight <= 1'b0;
      if (go || sqz_go) inflight <= 1'b1;

      if (init) begin
        state <= S_ABSORB; mode <= init_mode; err <= 1'b0;
        wcount <= '0; nbytes <= '0; first <= 1'b1;
        for (int i = 0; i < 34; i++) bufw[i] <= '0;
      end else begin
        if (go) begin
          // The core latched the block: free the buffer.
          for (int i = 0; i < 34; i++) bufw[i] <= '0;
          wcount <= '0; first <= 1'b0;
        end
        if (squeeze && !sqz_go) err <= 1'b1;
        if ((data_we || fin_we) && !in_ready) err <= 1'b1;
        unique case (state)
          S_ABSORB: begin
            if (in_ready && data_we) begin
              bufw[wcount] <= wdata;
              wcount <= wcount + 6'd1;
              nbytes <= nbytes + 64'd4;
            end else if (in_ready && fin_we) begin
              bufw[wcount] <= fin_word;
              wpad <= wcount;
              wcount <= wcount + 6'd1;
              nbytes <= nbytes + {62'b0, fin_cnt};
              state <= S_FIN;
            end
          end
          S_FIN: begin
            if (!is_sha) begin
              bufw[33] <= bufw[33] ^ 32'h8000_0000;  // pad10*1 last bit
              wcount <= 6'd34;
              state <= S_WAIT;
            end else if (wpad <= 6'd27) begin
              bufw[28] <= bswap(bitlen[127:96]);
              bufw[29] <= bswap(bitlen[95:64]);
              bufw[30] <= bswap(bitlen[63:32]);
              bufw[31] <= bswap(bitlen[31:0]);
              wcount <= 6'd32;
              state <= S_WAIT;
            end else begin
              wcount <= 6'd32;  // no room for the length: extra block
              state <= S_FIN_LEN;
            end
          end
          S_FIN_LEN: begin
            if (wcount == 6'd0) begin
              bufw[28] <= bswap(bitlen[127:96]);
              bufw[29] <= bswap(bitlen[95:64]);
              bufw[30] <= bswap(bitlen[63:32]);
              bufw[31] <= bswap(bitlen[31:0]);
              wcount <= 6'd32;
              state <= S_WAIT;
            end
          end
          S_WAIT: begin
            if (wcount == 6'd0 && !inflight) state <= S_DONE;
          end
          S_DONE: begin
            if (sqz_go) state <= S_SQZ;
          end
          S_SQZ: begin
            if (!inflight) state <= S_DONE;
          end
          default: ;
        endcase
      end
    end
  end

  /* verilator lint_off UNUSEDSIGNAL */
  logic unused_busy;
  assign unused_busy = sha_busy ^ kec_busy;
  /* verilator lint_on UNUSEDSIGNAL */
endmodule
`default_nettype wire
