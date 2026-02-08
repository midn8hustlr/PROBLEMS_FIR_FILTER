# What an Agent Must Do to Succeed: `fir_filter_symm_dec3`

## Problem Overview

The agent is given a skeleton Verilog module (`fir_filter_symm_dec3`) with only the module port declarations and 60 coefficient parameters defined. The task is to implement a complete, synthesizable, area-optimized **120-tap symmetric FIR filter with decimation by 3**. The baseline output port is intentionally declared as `output reg signed [7:0] y_out` (wrong width, wrong type), so the agent must fix the interface as well as fill in the entire datapath.

---

## The Hidden Grader Code

The hidden test file (`test_fir_filter_symm_dec3_hidden.py`) is a cocotb-based testbench with **six test cases** organized into two groups:

### Group 1: Impulse Response Tests (3 tests)

These tests apply a single impulse at `x[0]` and then drive `x_in = 0` for all subsequent cycles. They verify that the filter's decimated output stream matches `h[k] * impulse_value` at every third tap.

| Test | Impulse Value | What It Checks |
|------|--------------|----------------|
| `test_impulse_response_unit` | `+1` | Raw coefficient values appear at outputs (easiest to debug since expected = h[k]) |
| `test_impulse_response_scaled` | `+127` | Full-scale positive impulse — catches overflow/truncation bugs |
| `test_impulse_response_negative` | `-127` | Full-scale negative impulse — catches signed-arithmetic bugs |

**Key grader behaviors:**
- The grader **auto-detects phase alignment**: it does not require the first non-zero output at a specific cycle. Instead it scans up to 10 clock cycles for the first non-zero output, then checks which phase offset (0, 1, or 2) that value corresponds to. This means the grader is **latency-tolerant** — the agent's solution can have a different pipeline latency and still pass.
- Once alignment is detected, the grader samples `y_out` every 3 clock cycles and compares against `H[tap_idx] * impulse_value` for every decimated tap from `first_phase + 3` through tap 119.
- Every single decimated tap must match exactly — the grader counts passes vs. total and asserts 100% match.

### Group 2: Step Response Tests (3 tests)

These tests hold `x_in` at a constant value for the entire simulation and verify the filter's steady-state output equals `sum(H) * step_value` (where `sum(H) = sum(1..60) + sum(60..1) = 3660`).

| Test | Step Value | What It Checks |
|------|-----------|----------------|
| `test_step_response_unit` | `+1` | Steady-state = 3660 |
| `test_step_response_scaled` | `+127` | Steady-state = 464,820 — catches accumulator overflow |
| `test_step_response_negative` | `-127` | Steady-state = -464,820 — catches signed accumulator issues |

**Key grader behaviors:**
- The grader waits 140 clock cycles for the filter to settle (120 taps + pipeline margin).
- It reads a single `y_out` sample and compares to the exact expected value.
- The output is interpreted as a 23-bit signed value (`to_signed(val, 23)`), so the grader explicitly expects a 23-bit output port.

### Pytest Runner

The file ends with a `test_fir_filter_symm_dec3_runner()` function that uses `cocotb_tools.runner` to compile `sources/fir_filter_symm_dec3.v` with Icarus Verilog and execute all cocotb tests. This is the entry point that the HUD framework calls.

---

## What Aspects of the Golden Solution Earn It All Points

### 1. Correct Output Port Width and Type (critical for all 6 tests)

The baseline declares `output reg signed [7:0] y_out` — an 8-bit registered output. The golden solution changes this to:

```verilog
output wire signed [22:0]   y_out
```

The grader interprets `y_out` as a 23-bit signed value. The full dynamic range requires 23 bits:
- 8-bit input × 8-bit coefficient = 16-bit product
- Pre-addition of symmetric pair adds 1 bit → 9-bit pre-sum × 8-bit coeff = 17-bit product
- Summing 20 products adds ~5 bits → ~22 bits
- Accumulating 3 phases adds ~2 bits → 23 bits needed

If the agent leaves the output at 8 bits, every test will fail because the grader expects values up to ±464,820.

### 2. Phase Counter / Decimation-by-3 Timing (critical for all 6 tests)

The golden solution implements a 2-bit phase counter cycling `0 → 1 → 2 → 0 → ...`:

```verilog
reg [1:0] phase;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        phase <= 2'd0;
    else
        phase <= (phase == 2'd2) ? 2'd0 : phase + 2'd1;
end
```

This counter drives the entire time-multiplexed architecture. Without correct decimation-by-3 timing, the filter will not produce outputs at the right rate.

### 3. Three Polyphase Shift Registers (critical for impulse response tests)

The golden solution maintains three separate 40-element shift registers (`sr0`, `sr1`, `sr2`), each updated on its respective phase:

```verilog
reg signed [7:0] sr0 [0:39];
reg signed [7:0] sr1 [0:39];
reg signed [7:0] sr2 [0:39];

always @(posedge clk or negedge rst_n) begin
    ...
    case (phase)
        2'd0: begin
            for (i = 39; i > 0; i = i - 1) sr0[i] <= sr0[i-1];
            sr0[0] <= x_in_mx;
        end
        2'd1: begin
            for (i = 39; i > 0; i = i - 1) sr1[i] <= sr1[i-1];
            sr1[0] <= x_in_mx;
        end
        2'd2: begin
            for (i = 39; i > 0; i = i - 1) sr2[i] <= sr2[i-1];
            sr2[0] <= x_in_mx;
        end
    endcase
end
```

The 120-tap filter needs 120 samples, but since we decimate by 3, each sub-sequence only needs 40 entries (120/3). The impulse tests verify that each tap is correctly mapped to the right sub-sequence and delay index.

### 4. Correct Tap-to-Sample Mapping (critical for impulse response tests)

This is the trickiest combinational logic. The golden solution maps each of the 120 taps to the correct polyphase sub-sequence and delay:

```verilog
generate
    for (g = 0; g < 120; g = g + 1) begin : tap_map
        if (g % 3 == 0) begin : sub2
            if (g == 0)
                assign tap_sample[g] = x_in_mx;   // newest sample
            else
                assign tap_sample[g] = sr2[g/3 - 1];
        end else if (g % 3 == 1) begin : sub1
            assign tap_sample[g] = sr1[g/3];
        end else begin : sub0
            assign tap_sample[g] = sr0[g/3];
        end
    end
endgenerate
```

The mapping rule is: for output `y[3n+2]`, tap `k` uses `x[3n+2-k]`:
- `k % 3 == 0` → sub-sequence 2, delay `k/3` (with `g==0` special-cased to use `x_in` directly)
- `k % 3 == 1` → sub-sequence 1, delay `k/3`
- `k % 3 == 2` → sub-sequence 0, delay `k/3`

Getting this mapping wrong would cause the impulse response to show coefficient values at the wrong taps. The grader checks every single decimated tap, so any indexing error will be caught.

### 5. Symmetric Pre-Addition (critical for correct filter values)

The golden solution exploits coefficient symmetry by pre-adding symmetric sample pairs before multiplication:

```verilog
wire signed [8:0] pre_sum [0:59];
generate
    for (g = 0; g < 60; g = g + 1) begin : sym_add
        assign pre_sum[g] = tap_sample[g] + tap_sample[119 - g];
    end
endgenerate
```

Note the result is 9 bits (one extra bit from the addition of two 8-bit values). These are then registered in `sym_sum[0:59]` at the end of phase 2, which is when all three shift registers have been updated and the tap mapping is consistent.

### 6. Time-Multiplexed 20-Multiplier Architecture (critical for all tests)

The golden solution uses exactly 20 multipliers, each handling 3 coefficients across 3 phases:

```verilog
generate
    for (g = 0; g < 20; g = g + 1) begin : mul_gen
        wire signed [7:0] c0, c1, c2;
        assign c0 = COEFF[(3*g  )*8 +: 8];
        assign c1 = COEFF[(3*g+1)*8 +: 8];
        assign c2 = COEFF[(3*g+2)*8 +: 8];

        wire signed [7:0] m_coeff;
        assign m_coeff = (phase == 2'd0) ? c0 :
                         (phase == 2'd1) ? c1 : c2;

        wire signed [8:0] m_samp;
        assign m_samp = (phase == 2'd0) ? sym_sum[3*g]   :
                        (phase == 2'd1) ? sym_sum[3*g+1] : sym_sum[3*g+2];

        assign mul_prod[g] = m_coeff * m_samp;
    end
endgenerate
```

- Phase 0: multipliers process coefficients 0, 3, 6, ..., 57 (20 products)
- Phase 1: multipliers process coefficients 1, 4, 7, ..., 58 (20 products)
- Phase 2: multipliers process coefficients 2, 5, 8, ..., 59 (20 products)

This yields all 60 products across 3 cycles. The coefficient lookup uses a packed `localparam [479:0] COEFF` for indexed access.

### 7. Proper Accumulation Pipeline (critical for step response tests)

The golden solution accumulates the 20 multiplier outputs per phase, then sums across three phases:

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        accum <= 23'sd0;
        y_out_int <= 23'sd0;
    end else begin
        case (phase)
            2'd0: accum <= phase_sum;           // start fresh
            2'd1: accum <= accum + phase_sum;   // add second batch
            2'd2: y_out_int <= accum + phase_sum; // output total
        endcase
    end
end
```

The accumulator uses 23 bits, which is sufficient for the worst case of `sum(H) * 127 = 464,820`. The step response tests specifically check this full-scale value, so any truncation or overflow in the accumulator would fail.

### 8. Active-Low Asynchronous Reset (critical for all tests)

The golden solution uses `negedge rst_n` in every `always` block sensitivity list and initializes all state to zero on `!rst_n`. The grader drives `rst_n = 0` for several cycles at the start of every test and then releases it. Any block missing the async reset would retain uninitialized values and corrupt the filter state.

### 9. Latency Flexibility (enables different valid implementations)

The golden solution includes `INPUT_LATENCY` and `OUTPUT_LATENCY` parameters with optional pipeline registers on both input and output. While the defaults are 0, this design pattern demonstrates that the grader's auto-detection of phase alignment makes it tolerant of different pipeline depths. An agent's solution does not need these parameters — any implementation with correct functional behavior will pass, regardless of a few cycles of extra latency (up to 10 cycles).

---

## Summary: What a Good Solution Must Have

A successful agent solution needs to:

1. **Fix the output port** to be 23-bit signed (`signed [22:0]`), not 8-bit. The grader reads 23-bit values.
2. **Implement a phase counter** cycling through 3 states for decimation-by-3 timing.
3. **Maintain three polyphase shift registers** (40 entries each) that capture input samples on their respective phases.
4. **Correctly map all 120 taps** to the right sub-sequence and delay index, respecting the polyphase decomposition.
5. **Pre-add symmetric sample pairs** (`tap[k] + tap[119-k]`) to exploit coefficient symmetry and halve the multiplications.
6. **Implement time-multiplexed multipliers** that cycle through coefficient groups across 3 phases (20 multipliers × 3 phases = 60 products).
7. **Accumulate partial products** across 3 phases into a sufficiently wide (23-bit) accumulator.
8. **Use active-low asynchronous reset** on all sequential logic.
9. **Use proper signed arithmetic** throughout (signed coefficients, signed samples, signed products, signed accumulator) — the negative impulse and negative step tests catch unsigned bugs.
10. **Produce the filter output at the decimated rate** (one new output every 3 clock cycles) — the grader samples every 3 cycles after phase alignment detection.
