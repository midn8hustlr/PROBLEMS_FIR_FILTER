# Symmetric FIR Filter with Decimation by 3 (Area-Optimized)

Area-optimized 120-tap symmetric FIR filter with decimation by 3, using only 20 multipliers.

## Problem Description

Implement an area-optimized symmetric FIR filter that:
- Exploits **coefficient symmetry** (h[k] = h[119-k]) to pre-add sample pairs
- Uses **3-way polyphase decomposition** for decimation by 3
- Uses **time-domain multiplexing** to share 20 multipliers across 3 phases
- Achieves ~67% multiplier reduction (20 instead of 60)

## Key Challenges

1. Correct mapping of symmetric sample pairs across three polyphase shift registers
2. Proper timing for pre-sum computation (using x_in for newest sample)
3. TDM scheduling of coefficients and samples across 3 phases
4. Accumulation across three computation phases

## Directory Structure

```
├── sources/           # Verilog RTL source files
│   └── fir_filter_symm_dec3.v
├── tests/             # Cocotb test files
│   └── test_fir_filter_symm_dec3_hidden.py
├── docs/              # Specifications
│   └── Specification.md
├── prompt.txt         # Task description
└── pyproject.toml     # Python dependencies
```

## Running Tests

```bash
uv run pytest tests/test_fir_filter_symm_dec3_hidden.py -v -s
```
