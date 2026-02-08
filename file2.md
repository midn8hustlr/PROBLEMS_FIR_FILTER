# Failure Analysis Report: failed1

## 1. Discrepancy Summary

| Metric | Agent's Claim | Hidden Grader Result |
|--------|--------------|---------------------|
| Agent's own tests | "ALL TESTS PASSED!" (7/7) | N/A |
| Hidden grader score | N/A | **0.0 / 1.0** |
| Hidden test results | N/A | **2 PASS, 4 FAIL** out of 6 |

### Hidden Grader Breakdown

| Test | Status | Details |
|------|--------|---------|
| `test_impulse_response_unit` | **FAIL** | 12/40 decimated taps matched |
| `test_impulse_response_scaled` | **FAIL** | 12/40 decimated taps matched |
| `test_impulse_response_negative` | **FAIL** | Phase alignment detection failed entirely (first output = 8388481, expected one of [-127, -254, -381]) |
| `test_step_response_unit` | PASS | 3660 correct |
| `test_step_response_scaled` | PASS | 464820 correct |
| `test_step_response_negative` | **FAIL** | Got 7923788, expected -464820 |

---

## 2. Root Cause Classification: **Agent's Fault** (two independent bugs)

The specification and grader are consistent. The agent had sufficient information to produce a correct solution but made two critical errors.

---

## 3. Bug #1: Output Port Width — 24 bits instead of 23 bits

### Symptom
- Negative impulse test: grader reads first output as 8388481 (positive), can't match to any expected phase value [-127, -254, -381]. Test aborts immediately.
- Negative step test: grader reads steady-state as 7923788, expected -464820.
- Positive step tests pass (values fit within 22 bits, interpreted identically in both 23-bit and 24-bit).

### Bug
The agent declared:
```verilog
output reg signed [23:0] y_out   // 8(input)+1(preadd)+8(coef)+6(accumulate60)=23 bits
```

This is **24 bits** (`[23:0]`). The grader interprets the output as a 23-bit signed value using `to_signed(val, 23)`. For a 24-bit port with a negative value (e.g., -127 stored as 24-bit unsigned = 16,777,089), `to_signed(16777089, 23)` produces 8,388,481 — a large positive number that doesn't match any expected output.

The correct declaration (from the golden solution) is:
```verilog
output wire signed [22:0] y_out   // 23 bits
```

### Bad Assumption
The agent's own comment correctly states "=23 bits" but the Verilog declaration uses `[23:0]` (24 bits). The agent confused the **number of bits** (23) with the **MSB index** (should be 22, not 23). This is a classic off-by-one error between bit count and index.

Additionally, the agent used `reg` instead of `wire` for the output, though this has no functional impact in Icarus simulation.

---

## 4. Bug #2: Incorrect Tap-to-Polyphase Delay Line Mapping

### Symptom
Impulse response tests show a systematic pattern:
- **Taps 0–15** (first 6 decimated outputs): PASS — correct coefficient values
- **Taps 18–99** (middle 28 decimated outputs): FAIL — output values are shifted by +3 coefficient positions
- **Taps 102–117** (last 6 decimated outputs): PASS — correct coefficient values
- Score: 12/40 per impulse test

Specific examples from unit impulse test:
```
h[18]=19: y_out=41  (= H18 + H21 = 19+22)
h[21]=22: y_out=25  (= H24)
h[24]=25: y_out=28  (= H27)
...
h[57]=58: y_out=60  (= H59)
h[60]=60: y_out=57  (= H56)   ← reversal at midpoint
...
h[99]=21: y_out=0   (missing entirely)
```

### Bug
The agent's tap-to-polyphase mapping formula swaps `delay_p1` and `delay_p2` for taps where `k%3 == 1` and `k%3 == 2`.

**Agent's mapping** (from code comments at line 103-106):
```
k%3==0: delay_p0[k/3]       ← CORRECT
k%3==1: delay_p2[(k+2)/3]   ← WRONG (should be delay_p1)
k%3==2: delay_p1[(k+1)/3]   ← WRONG (should be delay_p2)
```

**Golden solution's mapping** (translated to agent's naming: golden sr2=agent p0, golden sr1=agent p1, golden sr0=agent p2):
```
k%3==0: delay_p0[k/3 - 1]  (with k=0 special-cased to x_in)
k%3==1: delay_p1[k/3]
k%3==2: delay_p2[k/3]
```

The agent swapped which delay line holds `k%3==1` samples (should be p1, agent used p2) and `k%3==2` samples (should be p2, agent used p1). This means for any tap not divisible by 3, the filter reads from the wrong polyphase sub-sequence.

### Why the step response still passes
The step response holds x_in constant at the same value for all cycles. This means all three delay lines fill with the same value. When p1 and p2 are swapped, the pre-additions still produce the same sums because both lines contain identical data. The bug only manifests when delay lines contain different data — i.e., during transient/impulse responses.

### Why taps 0–15 and 102–117 pass
These taps fall in the range where only the k%3==0 sub-sequence (delay_p0) has been reached by the impulse. Taps with k%3==1 or k%3==2 in these ranges read from p1/p2 which are all zeros, so the swap has no effect. The bug only becomes visible once the symmetric partner tap also contains non-zero data from the impulse.

### Bad Assumption
The agent derived the polyphase mapping formula (`(-k) mod 3`) mentally without running a Python script to verify it (the script execution failed with a tool error). The agent then manually enumerated all 60 tap pairs in the combinational block without cross-checking the formula against a known reference. The mental derivation swapped the assignment of `k%3==1` and `k%3==2` to sub-sequences.

---

## 5. Agent's Self-Verification Failure

The agent's own testbench was systematically inadequate at detecting these bugs:

### 5a. Impulse test was non-diagnostic
The agent's Test 1 ("Impulse Response") printed "Test 1: Impulse response complete" without checking any actual coefficient values. No pass/fail assertion was made.

### 5b. Worked backwards from DUT output
When the agent's Test 7 (reference model comparison) detected 27 errors, the agent:
1. First attributed the errors to testbench timing alignment, not a DUT bug
2. Replaced the failing test with a simpler "impulse sum" test
3. Computed the expected impulse sum (1220) by working **backwards from the DUT's behavior** — deriving which coefficients *should* contribute based on the (incorrect) polyphase mapping
4. Verified the DUT output matched this derived expectation and declared success

This is a critical reasoning failure: the agent validated the DUT against the DUT's own behavior, not against an independent reference.

### 5c. Wrong boundary value for negative test
The agent tested `x_in = -128` (8-bit minimum) in Test 6, getting -468480 = 3660 * (-128). The hidden grader tests `x_in = -127`, expecting -464820. The agent never tested -127 specifically, missing the signed arithmetic issue.

### 5d. No per-tap impulse verification
The hidden grader checks **every single decimated tap** of the impulse response for exact match. The agent never performed such a test. A simple check of whether y_out[n] equals h[n] for the impulse response would have revealed the mapping bug immediately.

---

## 6. Additional Design Differences from Golden Solution

| Aspect | Agent | Golden |
|--------|-------|--------|
| Output port | `reg signed [23:0]` (24-bit) | `wire signed [22:0]` (23-bit) |
| Delay line sizes | p0: 40, p1: 41, p2: 41 | sr0: 40, sr1: 40, sr2: 40 |
| Tap 0 handling | Via delay_p0[0] (1 cycle delayed) | Direct `x_in_mx` (current input) |
| Pre-add timing | Combinational in `always @(*)`, reads current delay state per phase | Registered at end of phase 2, ensures consistent snapshot |
| TDM coefficient grouping | Sequential: H0-19, H20-39, H40-59 | Interleaved: H[3g], H[3g+1], H[3g+2] per multiplier g |
| Coefficient storage | Individual parameters | Packed `localparam [479:0] COEFF` |

---

## 7. Summary

This is an **Agent's Fault** failure. The agent had the specification and enough domain knowledge to derive the correct polyphase mapping and output width. Two bugs prevented passing:

1. **Output width off-by-one**: Comment says 23 bits, declaration says `[23:0]` = 24 bits. Causes all negative-value tests to fail (2 of 6 tests).

2. **Polyphase mapping swap**: delay_p1 and delay_p2 assignments reversed for k%3==1 and k%3==2 taps. Causes 28/40 impulse response taps to produce wrong values (3 of 6 tests). Only masked for step response where all delay lines hold identical values.

The agent's self-verification was insufficient — it never checked per-tap impulse response values against known coefficients, and rationalized away the one test (reference model comparison) that DID detect the bug.
