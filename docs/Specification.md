# Specification: Symmetric FIR Filter with Decimation by 3

## 1. FIR Filter Basics

A Finite Impulse Response (FIR) filter computes a weighted sum of input samples:

```
y[n] = Σ h[k] * x[n-k]  for k = 0 to N-1
```

Where:
- `x[n]` is the input signal
- `y[n]` is the output signal
- `h[k]` are the filter coefficients (N taps)

## 2. Symmetric Coefficients

A symmetric FIR filter has coefficients where `h[k] = h[N-1-k]`. For a 120-tap filter:
- h[0] = h[119]
- h[1] = h[118]
- h[2] = h[117]
- ... and so on

This means only N/2 = 60 unique coefficients are needed.

### Exploiting Symmetry

With symmetric coefficients, the filter equation can be rewritten:

```
y[n] = h[0]*(x[n] + x[n-(N-1)]) + h[1]*(x[n-1] + x[n-(N-2)]) + ... + h[N/2-1]*(x[n-(N/2-1)] + x[n-N/2])
```

By **pre-adding symmetric sample pairs** before multiplication, we halve the number of multiplications.

## 3. Decimation by 3

With decimation by 3, only every third output sample is computed:

```
y[3n+p] = Σ h[k] * x[3n+p-k]  for k = 0 to N-1
```

where p is the phase offset. This means we have 3 input clock cycles available per output sample.

## 4. Polyphase Decomposition (3-way)

With decimation by 3, the input is split into three sub-sequences based on sample index modulo 3:
- **Sub-sequence 0**: x_0[m] = x[3m] → {x[0], x[3], x[6], ...}
- **Sub-sequence 1**: x_1[m] = x[3m+1] → {x[1], x[4], x[7], ...}
- **Sub-sequence 2**: x_2[m] = x[3m+2] → {x[2], x[5], x[8], ...}

Each sub-sequence is stored in its own shift register (delay line), updated on its respective clock phase.

For the decimated output, each sample x[3n+p-k] belongs to one of the three sub-sequences depending on (3n+p-k) mod 3. The designer must derive which sub-sequence and delay index corresponds to each tap k.

## 5. Combining Symmetry with 3-Way Polyphase Decomposition

When both optimizations are applied together:
1. Map each filter tap to its polyphase sub-sequence and delay index
2. Identify the symmetric pairs (tap k and tap N-1-k)
3. Note that symmetric pairs may cross between different sub-sequences
4. Pre-add the corresponding samples from the appropriate delay lines
5. Multiply each pre-added sum by its shared coefficient

The challenge is correctly deriving the register indices across three delay lines for each of the N/2 symmetric pairs.

## 6. Time-Domain Multiplexing (TDM)

When decimation provides multiple clock cycles per output, multipliers can be time-shared:
- Divide the N/2 multiplications into groups
- Compute one group per clock cycle using shared multiplier hardware
- Accumulate partial results across all cycles

With 3 available cycles, M multipliers can handle 3M multiplications total.

## 7. Fixed-Point Arithmetic and Bitwidth Growth

In fixed-point hardware, signal bitwidths grow with each arithmetic operation:

- **Addition/Subtraction**: Adding two N-bit signed values produces an (N+1)-bit result.
- **Multiplication**: Multiplying an A-bit signed value by a B-bit signed value produces an (A+B)-bit result.
- **Accumulation**: Summing M values each of W bits requires W + ceil(log2(M)) bits to avoid overflow.

The designer must trace bitwidth growth through the entire datapath—from input samples through pre-addition, multiplication, and final accumulation—to determine the minimum output width that prevents overflow across the full dynamic range.
