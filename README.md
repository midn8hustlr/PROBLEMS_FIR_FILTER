# Symmetric FIR Filter with Decimation by 3 (Area-Optimized)

Area-optimized 120-tap symmetric FIR filter with decimation by 3, using only 20 multipliers.

## Motivation and Industry Relevance

### Why FIR Filters?

FIR filters are one of the most fundamental building blocks in digital signal processing (DSP) hardware. They appear in virtually every communication system, audio/video processing pipeline, and sensor interface:

- **Wireless communications (4G/5G)**: Channel filtering, pulse shaping (root-raised-cosine filters), and anti-aliasing in base stations and handsets. A single 5G NR base station may instantiate dozens of FIR filters per antenna path.
- **Software-defined radio (SDR)**: Channelization filters that separate frequency bands in multi-carrier systems.
- **Audio processing**: Sample-rate conversion in DACs/ADCs, equalizers in hearing aids and consumer audio.
- **Radar and LIDAR**: Matched filtering and pulse compression in automotive and aerospace systems.
- **Biomedical devices**: Noise rejection in ECG/EEG acquisition ASICs where power and area are tightly constrained.

### Why This Specific Problem is Non-Trivial

A naive 120-tap FIR requires 120 multipliers — the most area- and power-expensive components in a DSP datapath. Real-world silicon designs never implement filters this way. Instead, experienced RTL engineers apply a combination of well-known but tricky-to-implement optimizations:

1. **Coefficient symmetry exploitation** — pre-adding symmetric sample pairs halves the multiply count from 120 to 60. This is standard practice in linear-phase filter design for telecom ASICs.
2. **Polyphase decomposition** — a structural decomposition that is the standard approach for implementing decimation/interpolation filters in hardware. Every multi-rate DSP system (sample-rate converters, channelizers, digital down-converters) relies on this technique.
3. **Time-domain multiplexing (TDM)** — sharing multiplier hardware across clock cycles is the primary area-optimization strategy in ASIC and FPGA DSP design. It directly trades throughput margin for silicon area, a tradeoff that engineers make on every real project.

Combining all three techniques in a single design — correctly mapping symmetric pairs across three polyphase sub-sequences, scheduling 60 multiply-accumulate operations onto 20 physical multipliers over 3 phases, and managing the accumulation and output timing — is representative of the kind of multi-layered structural reasoning that production RTL demands.

### Why This is a Good RL Training Problem

This problem tests capabilities that are critical for an LLM to be useful as a hardware design assistant:

- **Architectural reasoning**: The agent must understand and combine three distinct optimization strategies (symmetry, polyphase, TDM) rather than just translating a formula to RTL.
- **Index arithmetic**: Correctly deriving which samples to pre-add across three separate delay lines requires careful modular arithmetic — a common source of off-by-one bugs in real designs.
- **Datapath sizing**: Tracing bitwidth growth through pre-addition, multiplication, and accumulation is a practical skill that prevents silent overflow bugs in silicon.
- **Control logic**: Managing a 3-phase TDM schedule with proper output valid signaling exercises finite-state-machine design skills.
- **Synthesizability awareness**: The solution must avoid simulation-only constructs and produce hardware-realizable RTL.

The problem sits in a sweet spot of difficulty: it is too complex for template-matching or simple pattern completion, yet it has a well-defined correct answer that can be verified through simulation. This makes it ideal for RL-based training where the reward signal comes from passing functional tests.

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
