# Symmetric FIR Filter with Decimation by 2 (Area-Optimized)

Area-optimized 16-tap symmetric FIR filter with decimation by 2, using only 4 multipliers.

## Problem Description

Implement an area-optimized symmetric FIR filter that:
- Exploits **coefficient symmetry** (h[k] = h[15-k]) to pre-add sample pairs
- Uses **polyphase decomposition** for decimation by 2
- Uses **time-domain multiplexing** to share 4 multipliers across 2 phases
- Achieves 75% multiplier reduction (4 instead of 16)

## Key Challenges

1. Correct mapping of symmetric sample pairs across odd/even polyphase registers
2. Proper timing for pre-sum computation (using x_in for newest sample)
3. TDM scheduling of coefficients and samples
4. Accumulation across two computation phases

## Directory Structure

```
├── sources/           # Verilog RTL source files
│   └── fir_filter_dec2.v
├── tests/             # Cocotb test files
│   └── test_fir_filter_dec2.py
├── docs/              # Specifications
│   └── Specification.md
├── prompt.txt         # Task description
└── pyproject.toml     # Python dependencies
```

## Running Tests

```bash
pytest tests/test_fir_filter_dec2.py -v
```
