# Step 3: pipelined AES-128 and its integration into the RV32I SoC

This step takes the AES-128 encryptor from
[AES_VERILOG](https://github.com/anhtu0310/AES_VERILOG), fixes and rewrites
it, adds a fully pipelined version, and connects it to the CPU from steps 1
and 2 as a memory-mapped accelerator with a C driver and tests.

| | Original core | New `aes128_iter` | New `aes128_pipe` |
|---|---|---|---|
| Clocks per block | 102 | 10 | 1 (after 10 clocks of latency) |
| Synthesizable | no (latches, combinational loops) | yes | yes |
| Xilinx 7-series LUT / FF (Yosys) | - | 2.5k / 0.56k | 15.1k / 3.9k |
| Different key per block | no | yes | yes, while blocks are in flight |

On the SoC, one block costs about 5,600 clocks in software on the RV32I core
and about 36 clocks with the accelerator (streamed), a speed-up of roughly
**157x**.

Contents

1. [Review of the original AES code](#1-review-of-the-original-aes-code)
2. [The new AES cores](#2-the-new-aes-cores)
3. [Verification of the cores](#3-verification-of-the-cores)
4. [Integration into the SoC](#4-integration-into-the-soc)
5. [Software](#5-software)
6. [SoC-level verification](#6-soc-level-verification)
7. [Results](#7-results)
8. [Pipelined or iterative?](#8-pipelined-or-iterative)
9. [Files added or changed](#9-files-added-or-changed)
10. [Limitations and next steps](#10-limitations-and-next-steps)

---

## 1. Review of the original AES code

The original design lives in `Verilog/src/` at commit `c917910` of
AES_VERILOG: `AES_encryptor.v` (top FSM), `kay_scheduler2.v`,
`sub_byte.v`, `shift_rows.v`, `mix_cols.v`. The README already noted it
took "up to 103 clk" per block and was not finished.

**What works.** The algorithm is right. Simulated with Icarus Verilog
(`-g2005`) on the FIPS-197 Appendix C.1 vector, it produces the correct
ciphertext `69c4e0d8...c55a` after 102 clocks. The 100 test vectors made by
the C++ model (`CPP/aes_encryption.cpp`) are also correct: all 100 match an
independent AES (Python `cryptography`, OpenSSL-backed). The ShiftRows
wiring and the MixColumns column formula (`b_i = a_i ^ t ^ xtime(a_i ^ a_i+1)`)
are correct and are kept in the new code.

**What is wrong.** The design only works because of how a simulator
schedules events. Synthesis turns it into latches and combinational loops,
so it would not work on an FPGA.

| # | Where | Problem | Effect |
|---|---|---|---|
| 1 | `AES_encryptor.v:54-111` | The FSM's combinational `always` block also assigns `state`, `round_cnt` and `cipher_text`, and does `round_cnt = round_cnt + 1` (line 99). The sensitivity list is incomplete. | Yosys infers latches for `state` (128 bit), `cipher_text` (128 bit), `round_cnt` and `next_state`. The `round_cnt + 1` is a latch feeding itself, a combinational loop. In simulation it increments once only because the block wakes once per state change. |
| 2 | `kay_scheduler2.v:22-33` | `always @(round_cnt) prev_key = round_key;` where `round_key` is computed from `prev_key`. Same for `rcon`. | A combinational loop. The "previous key" has no storage in hardware; it exists only in the simulator's event order. |
| 3 | `sub_byte.v:70`, `mix_cols.v:72` | Each case branch assigns only one 32-bit quarter of `state_out`. `mixcols_dp` reads `round_cnt` but it is missing from the sensitivity list. | Four 32-bit latches per module; simulation and synthesis disagree. |
| 4 | `sub_byte.v:39-53`, `mix_cols.v:38-55` | The control units mix an asynchronous reset with a synchronous `~enable` in one `if`, and use a blocking `local_cnt = local_cnt + 1` in a clocked block. | Lint errors; race-prone in simulation. |
| 5 | `AES_encryptor.v:20-37` | `rst_n` of the SubBytes and MixColumns units is not connected. | The reset input floats (`z`/`x` in simulation). |
| 6 | `AES_encryptor.v:106-109` | `done` is a combinational decode of the FSM state and `cipher_text` is a latch. | Glitchy `done`; output not registered. |
| 7 | `sub_byte.v:56-100`, `mix_cols.v` | SubBytes and MixColumns each process one column per clock, with a handshake per step. | 102 clocks per block, about 10 times slower than one round per clock. |
| 8 | `mix_cols.v:117` | A function argument is called `byte`, a SystemVerilog keyword. | The file fails to compile in SystemVerilog mode (`iverilog -g2012`, Verilator). |
| 9 | `sub_byte.v:109-248` | The gate-level S-box is copied from the secworks AES core (J. Strombergson, BSD licence) without its licence header. | Licence attribution missing. On an FPGA the gate form also needs more LUTs than a table (a table S-box maps to exactly 32 LUT6 + 24 MUXF7/F8). |
| 10 | `*_tb` modules | No checking, no `$finish`, `start` stays high forever, inputs start as `x`. | The testbenches only produce waveforms to inspect by eye. |
| 11 | `CPP/aes_encryption.cpp` | Keys and plaintexts are 16 characters of a shuffled alphanumeric string (printable bytes, no byte repeats). `alloc_size` is `uint8_t`, so inputs over 255 bytes wrap; the buffer is never freed. A compiled binary is committed. | Weak test coverage (e.g. bytes `0x00` or `0xff` never occur); memory bugs. |
| 12 | names | `AES_encrptor`, `kay_scheduler2.v`, `plan_text_out`. | Typos. |

The Yosys log of the original (14 latches) is in the Step 3 artifacts
(`logs/original_yosys_check.log`).

---

## 2. The new AES cores

All new code is plain Verilog-2005, lints clean with Verilator `-Wall`,
and has no latches or combinational loops.

### 2.1 Building blocks: `aes_functions.vh`

Every AES step is a constant-time combinational function, shared by both
cores:

| Function | Does |
|---|---|
| `aes_sbox(x)` | S-box, a 256-entry `case` table (`aes_sbox.vh`, generated) |
| `aes_sub_bytes`, `aes_sub_word` | S-box on 16 / 4 bytes |
| `aes_shift_rows` | row r rotated left by r |
| `aes_mix_column(s)` | the MixColumns matrix, via `xtime` |
| `aes_next_key(k, rcon)` | one step of the key expansion |
| `aes_rcon(round)` | round constant 1..10 |
| `aes_round(s, k, final)` | SubBytes, ShiftRows, MixColumns (skipped if `final`), AddRoundKey |

State layout follows FIPS-197: byte 0 (`in0`) is bits `[127:120]`, column
`c` is the 32-bit word `[127-32c -: 32]`.

The S-box table is not typed by hand. `tools/aes_ref.py sbox-vh` computes
it from the definition (multiplicative inverse in GF(2^8), then the affine
transform), so the RTL and the Python reference model do not share a
hand-copied table.

### 2.2 `aes128_iter`: one round per clock

```
         in_block ^ in_key                  +--> out_block (registered)
              |                             |
   load  +----v----+   +-------------------+-+
  ------>|  state  |-->| aes_round(state,  | |
         +----^----+   |   next_key, last) |-+
              |        +-------------------+
              +-----------------+
         +---------+   +-------------------+
  in_key>|  rkey   |-->| aes_next_key(rkey,|----> next_key
         +---------+   |   rcon)           |
         +---------+   +-------------------+
         |  rcon   |--> xtime(rcon)
         +---------+
```

One round datapath (16 + 4 S-boxes) is reused ten times. A block is taken
on `in_valid && in_ready`; `out_valid` pulses 10 clocks later. `in_ready`
is already high in the clock the last round runs, so blocks can follow
every 10 clocks with no gap. This is the "improved original": the same
iterative idea, 10x faster, synthesizable, with a valid/ready interface.

### 2.3 `aes128_pipe`: ten-stage pipeline

```
 in_block, in_key, in_tag, in_valid
     |
     v
 [stage 1]  s1 = Round(in ^ K0, K1)   K1 = NextKey(K0, 01)
     |
 [stage 2]  s2 = Round(s1, K2)        K2 = NextKey(K1, 02)
     |
    ...
 [stage 10] s10 = FinalRound(s9, K10) K10 = NextKey(K9, 36)
     |
     v
 out_block, out_tag, out_valid        (10 clocks after the input)
```

* The ten rounds are unrolled; each stage has its own 16 S-boxes plus 4 for
  its key step (200 S-boxes in total).
* The key expansion is pipelined too: each stage computes its round key
  from the key in the previous stage and passes it on. The key therefore
  travels with its block, so every block may use a different key and
  software can change the key register while earlier blocks are in flight.
  (The alternative, expanding the key once into 11 stored round keys, saves
  40 S-boxes but forces a pipeline drain on every key change.)
* `in_tag` (any width) travels with the block, so a user can match results
  to requests.
* `ce` is a global clock enable for back-pressure: with `ce = 0` the whole
  pipeline holds.
* Data registers have no reset, only the 10 valid bits do; this keeps the
  FPGA mapping simple.
* AddRoundKey(K0) is folded into stage 1, so latency is 10 clocks, not 11.

Each stage's logic is one S-box (one LUT6 level plus the F7/F8 muxes), the
MixColumns XORs and the AddRoundKey XOR, in parallel with the key step.
This is about 4 to 5 LUT levels, which should be comfortable at 100 MHz on
Artix-7; it was not timed here (only open-source Yosys was available, which
does not do timing analysis), so check it in Vivado.

---

## 3. Verification of the cores

### 3.1 Reference model: `tools/aes_ref.py`

Pure Python, no packages needed (so CI can run it). It is checked against:

* FIPS-197 Appendix B and C.1 and the Appendix A.1 key expansion;
* NIST SP 800-38A F.1.1 (ECB-AES128, four blocks);
* 300 random blocks compared with the `cryptography` package (OpenSSL), run
  once by hand.

It writes random vectors (`vectors`), the C header for the firmware test
(`c-header`) and the S-box table for the RTL (`sbox-vh`).

### 3.2 Core testbench: `tb/tb_aes.v` (AES repo), `tb/tb_aes_core.v` (SoC repo)

Reads "key plaintext ciphertext" lines (the 6 known vectors, then N random
ones, plus the 100 original C++ vectors in the AES repo) and checks:

| Test | Checks |
|---|---|
| iter, single blocks | every vector; latency exactly 10 clocks; inputs are only sampled on the accepting clock (they are scrambled right after) |
| iter, back-to-back | `in_valid` held high: every result right, one block per 10 clocks |
| pipe, streaming | one block per clock, nothing out before 10 clocks, N blocks in N + 10 clocks, results in order (via `in_tag`) |
| pipe, bubbles and stalls | random gaps on `in_valid` and random `ce = 0` cycles (about 25 %), a different key on every block, junk inputs while stalled; every result checked in order; no extra results |

Results: AES repo `make test` with 206 + 100 vectors, 1,836 checks, 0
errors; SoC repo `make aes-core` with 206 vectors, 1,236 checks, 0 errors.

---

## 4. Integration into the SoC

### 4.1 Where it sits

The accelerator is a fifth peripheral page, decoded in `rtl/soc_top.v` like
the others:

| Address | Device |
|---|---|
| `0x1000_0000` | GPIO |
| `0x1000_1000` | UART |
| `0x1000_2000` | I2C |
| `0x1000_3000` | SPI |
| **`0x1000_4000`** | **AES (`rtl/periph/aes_accel.v`)** |

It uses the same slave interface as the step 2 peripherals (`sel`, `we`,
`re`, word `addr`, `wdata`, `wstrb`, registered `rdata` the next clock), so
no change to the CPU or the bus was needed. The SoC parameter
`AES_PIPELINED` (also on `fpga_top`) picks the core: 1 (default) for
`aes128_pipe`, 0 for `aes128_iter`. Both give the same registers and
results.

```
            CPU data bus (MEM stage)
                    |
     +--------------v---------------------------------------------+
     | aes_accel                                                   |
     |  KEY0..3 --+                                                |
     |  DIN0..3 --+--> bswap --> aes128_pipe / aes128_iter --+     |
     |  CMD.START or DIN3 write (AUTO_START)    (epoch tag)  |     |
     |                                                        v     |
     |  STATUS <-- READY, OUT_VALID, counts      16 x 128-bit FIFO  |
     |  DOUT0..3 <-- bswap <-- FIFO head <------------------+       |
     +-------------------------------------------------------------+
```

### 4.2 Registers (word offsets from `0x1000_4000`)

| Offset | Name | Access | Bits |
|---|---|---|---|
| `0x00` | CTRL | RW | `[0]` AUTO_START: a write to DIN3 also starts the block |
| `0x04` | STATUS | R | `[0]` READY, `[1]` OUT_VALID, `[2]` BUSY, `[3]` OVERFLOW (sticky), `[12:8]` OUT_COUNT, `[19:16]` IN_FLIGHT, `[31]` PIPELINED |
| `0x08` | CMD | W | `[0]` START, `[1]` CLEAR |
| `0x0C` | BLOCKS | R | blocks completed since reset |
| `0x10`-`0x1C` | KEY0..3 | RW | key, byte-lane writes allowed |
| `0x20`-`0x2C` | DIN0..3 | RW | plaintext block, byte-lane writes allowed |
| `0x30`-`0x3C` | DOUT0..3 | R | oldest result, 0 when none; reading DOUT3 pops it |

### 4.3 Design decisions

**Byte order.** Register word `i` holds block bytes `4i..4i+3` with byte
`4i` in bits `[7:0]`. On this little-endian CPU a 16-byte buffer read as
four `uint32_t` words goes straight into KEY/DIN and comes straight out of
DOUT, so the driver does no byte shuffling. The accelerator swaps bytes to
the cores' FIPS order internally (wiring only, no logic).

**Several blocks in flight.** START captures the key and the block
together and pushes them into the core. The CPU can then load the next key
and block at once. Results go into a 16-entry FIFO in issue order.

**No lost results (credits).** The pipeline cannot be stopped from the
FIFO side, so READY is only high when `IN_FLIGHT + OUT_COUNT < 16` (and the
core can accept). That guarantees a slot for every block already in the
pipeline. A START while not READY is ignored and sets the sticky OVERFLOW
flag, so software errors are visible rather than silent.

**CLEAR.** Results carry a 4-bit epoch tag through the core (the
pipeline's `in_tag`). CLEAR empties the FIFO and bumps the epoch; results
of blocks still in flight come out with the old epoch and are dropped.
OVERFLOW is cleared too.

**AUTO_START** saves one store per block: with it set, the DIN3 write
starts the block, using the value being written in that same clock.

**Polling only.** Like the step 2 peripherals there are no interrupts
(the core has no interrupt support yet).

### 4.4 Cost of the accelerator wrapper

`aes_accel` itself (registers, FIFO, control) is 353 LUT, 348 FF and 22
LUTRAM cells (the 16 x 128-bit FIFO).

---

## 5. Software

### 5.1 Register map and driver

`sw/common/soc.h` has the addresses and bit names (`AES_BASE`,
`AES_STATUS`, `AES_READY`, ...). `sw/common/periph.h` has the driver:

```c
#include "periph.h"

static const uint32_t key[4] = { 0x16157e2b, 0xa6d2ae28, 0x8815f7ab, 0x3c4fcf09 };
uint32_t in[4], out[4];

aes_encrypt_block(key, in, out);          // one block, waits for it
aes_ecb_encrypt(key, src, dst, nblocks);  // stream: push while READY, pop while OUT_VALID
```

Lower-level helpers: `aes_status()`, `aes_set_key()`, `aes_push()`,
`aes_pop()`. `aes_ecb_encrypt` uses AUTO_START and keeps up to 16 blocks
queued or in flight. Buffers are `uint32_t` arrays (4-byte aligned) holding
the bytes in FIPS order.

### 5.2 Software AES

`sw/common/aes_soft.h` is a small byte-oriented AES-128 in C (no lookup
tables apart from the S-box). It is used to cross-check the hardware and
as the speed baseline.

---

## 6. SoC-level verification

| Test | Command | What it does |
|---|---|---|
| `tb/tb_aes_core.v` | `make aes-core` | both cores, section 3.2 |
| `tb/tb_aes_accel.v` | `make aes-unit` | register-level tests of `aes_accel`, run on a pipelined and an iterative instance |
| `sw/periph/aes_test.c` | `make aes-sw` | firmware on the full SoC, both core options |
| `sw/periph/aes_bench.c` | `make aes-sw` | speed comparison, both core options |

All are part of `make test`, so CI runs them.

**`tb_aes_accel` (458 checks).** For each core option: reset values;
register read-back and byte lanes; FIPS-197 C.1 through CMD.START with
BUSY/OUT_VALID/OUT_COUNT; two blocks with the key changed while the first
is in flight; SP 800-38A's four blocks with AUTO_START, read afterwards;
filling all 16 FIFO entries, with the 17th START refused and flagged;
the credit rule (with 12 results queued, STARTs every 2 clocks are accepted
only until queued + in flight reaches 16); CLEAR dropping both queued and
in-flight results; BLOCKS counting.

**`aes_test.c`** runs on the CPU in the lockstep testbench (every
instruction is checked against the reference model, loads from the
accelerator are taken from the RTL). It checks the reset state; FIPS-197 B
and C.1 one block at a time; SP 800-38A ECB streamed; 32 vectors (6 known
+ 26 random from `aes_ref.py`, in `sw/periph/aes_vectors.h`) streamed with
**a different key for every block**, so the key register changes while
earlier blocks are still inside the pipeline; the software AES against the
same vectors; the block counter; and CLEAR.

**`aes_bench.c`** encrypts the same data three ways and checks they agree:
4 blocks in software, 4 blocks with `aes_encrypt_block`, and 64 blocks with
`aes_ecb_encrypt`. It writes markers to a simulation-only address
(`MARK_ADDR = 0xF000_0004`); `tb_soc` prints the cycle count at each
marker (`[mark] 3 at cycle 26893 (+235)`).

**Do the tests catch bugs?** Ten bugs were injected one at a time; all ten
were caught (`logs/mutation_results.txt` in the artifacts):

| Injected bug | Caught by |
|---|---|
| wrong Rcon in round 9 | core, accel |
| wrong MixColumns term | core, accel |
| pipeline stage 6 uses the previous round key | core, accel |
| pipeline valid bit one stage short | core, accel |
| iterative core not ready in its last round | core, accel |
| results of CLEARed blocks still queued | accel |
| READY ignores blocks in flight (credit bug) | accel |
| DOUT1 without byte swap | accel |
| AUTO_START uses the old DIN3 value | accel |
| byte-lane strobes ignored | accel |

---

## 7. Results

### 7.1 Tests

`make test SEEDS="1 .. 20"` (as in CI): 37 runs, all `TEST PASSED`:
unit tests, 4 ISA tests, C test, peripheral register tests, 4 peripheral
firmware tests, AES core, AES accelerator, `aes_test` and `aes_bench` on
both core options, and 20 random lockstep programs. `make lint` (Verilator
`-Wall`, `soc_top` and `fpga_top`) is clean. The committed `sw/build/*.hex`
images rebuild bit-identically.

### 7.2 Speed (from `aes_bench`, 100 MHz clock assumed for the last column)

| Method | Clocks per block | Blocks per second at 100 MHz | vs software |
|---|---|---|---|
| Software AES on the RV32I core (`aes_soft.h`, `-O2`) | 5,645 | 17.7 k (2.3 Mbit/s) | 1x |
| Accelerator, one block at a time | 59 | 1.7 M | 96x |
| Accelerator, streamed (`aes_ecb_encrypt`) | 36 | 2.8 M (356 Mbit/s) | **157x** |
| `aes128_pipe` alone, fed every clock | 1 | 100 M (12.8 Gbit/s) | |
| `aes128_iter` alone | 10 | 10 M (1.28 Gbit/s) | |

The streamed figure is the same with the pipelined and the iterative core
(2,302 vs 2,304 clocks for 64 blocks); see section 8.

### 7.3 FPGA resources (Yosys `synth_xilinx`, 7-series, `fpga_top`)

| Build | LUT | FF | BRAM36 |
|---|---|---|---|
| Step 2 SoC (no AES) | ~1.8 k | ~0.8 k | 4 |
| SoC + `aes128_pipe` (`AES_PIPELINED=1`) | 17.3 k | 5.1 k | 4 |
| SoC + `aes128_iter` (`AES_PIPELINED=0`) | 4.7 k | 1.7 k | 4 |

Of the pipelined build, `aes128_pipe` is 15.1 k LUT and 3.9 k FF; 6.4 k of
those LUTs are the 200 S-boxes. The pipelined SoC fits an Artix-7 35T
(20.8 k LUT, about 83 %) and easily a 50T/100T; on a smaller part use
`AES_PIPELINED=0`. Per-module tables are in `logs/synth_summary*.txt`.

---

## 8. Pipelined or iterative?

The pipeline does what it should: one block per clock, 12.8 Gbit/s at
100 MHz. But the CPU cannot feed it that fast. Each block needs 4 stores
and 4 loads over a 32-bit bus plus a status read and loop overhead, about
36 clocks per block with this simple in-order core. The iterative core
finishes a block every 10 clocks, so it already keeps up with the CPU,
and the measured streaming speed is the same for both (section 7.2), while
the iterative core needs less than a fifth of the logic.

So, as integrated here (CPU moves the data):

* `AES_PIPELINED=1` (the default, as asked) shows the pipeline working
  inside the SoC and is ready for a faster data source.
* `AES_PIPELINED=0` gives the same software speed for 4.7 k instead of
  17.3 k LUTs, and is the better choice if the FPGA is small.

The pipeline pays off once data reaches it without the CPU: a DMA engine
that streams blocks from RAM, or a 128-bit streaming port to another
block (Ethernet, a camera, a memory controller). `aes128_pipe`'s
`in_valid`/`ce`/`in_tag` interface is made for that.

---

## 9. Files added or changed

AES_VERILOG (branch `claude/aes-pipeline-integration-u4slkp`):

| File | |
|---|---|
| `Verilog/rtl/aes_functions.vh` | new: AES building blocks |
| `Verilog/rtl/aes_sbox.vh` | new, generated S-box table |
| `Verilog/rtl/aes128_iter.v` | new: iterative core |
| `Verilog/rtl/aes128_pipe.v` | new: pipelined core |
| `Verilog/tb/tb_aes.v` | new: self-checking testbench |
| `Verilog/tb/vectors_legacy.txt` | the 100 original C++ vectors (verified) |
| `Verilog/tools/aes_ref.py` | new: reference model and generators |
| `Verilog/Makefile` | new: `test`, `lint`, `synth`, `selftest` |
| `Verilog/src/` | removed (original design; in git history) |
| `CPP/aes_encryption.cpp` | `alloc_size` overflow and leak fixed |
| `CPP/aes` | removed compiled binary; `.gitignore` added |
| `README.md`, `docs/AES.md` | rewritten / this document |

RISC-V-Pipeline-Verilog (branch `claude/aes-pipeline-integration-u4slkp`,
on top of step 2):

| File | |
|---|---|
| `rtl/aes/*` | copy of the AES cores and headers |
| `rtl/periph/aes_accel.v` | new: the accelerator |
| `rtl/soc_top.v` | AES page at `0x1000_4000`, `AES_PIPELINED` parameter |
| `rtl/fpga/fpga_top.v` | passes `AES_PIPELINED` |
| `sw/common/soc.h`, `periph.h` | AES registers and driver, `MARK_ADDR` |
| `sw/common/aes_soft.h` | new: software AES |
| `sw/periph/aes_test.c`, `aes_bench.c`, `aes_vectors.h` | new firmware and vectors |
| `sw/build/aes_*.hex/.dis` | pre-built images |
| `tb/tb_aes_core.v`, `tb/tb_aes_accel.v` | new testbenches |
| `tb/tb_soc.v` | `AES_PIPELINED` parameter, cycle markers |
| `tools/aes_ref.py` | reference model (same as in AES_VERILOG) |
| `Makefile` | `aes`, `aes-core`, `aes-unit`, `aes-sw`, `aes-vectors`; `test` runs AES too |
| `README.md`, `docs/AES.md` | memory map, this document |

---

## 10. Limitations and next steps

* **Encryption only.** Decryption (inverse cipher) is not implemented. ECB
  is what the hardware does; modes such as CTR, CBC or GCM are built in
  software on top of it (CTR is just encrypting a counter, which streams
  well).
* **AES-128 only**, no 192/256-bit keys.
* **No timing analysis** was possible with the open-source tools here.
  The per-stage logic is shallow, but run Vivado on the real part before
  relying on 100 MHz.
* **No DMA.** The CPU moves every word, which limits throughput to about
  36 clocks per block (section 8). A small DMA or streaming port would let
  the pipeline run at full rate.
* **No side-channel hardening.** The cores are constant-time (no
  data-dependent timing), but there is no protection against power or
  fault attacks, and keys stay readable in KEY0..3 until overwritten.
* **No interrupts.** Software polls STATUS, as with the other peripherals.
