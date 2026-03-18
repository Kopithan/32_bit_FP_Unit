# 32-bit Floating Point Arithmetic Unit

![IEEE 754](https://img.shields.io/badge/Standard-IEEE%20754%20Single%20Precision-0EA5E9?style=for-the-badge)
![Language](https://img.shields.io/badge/RTL-SystemVerilog-14B8A6?style=for-the-badge)
![Ops](https://img.shields.io/badge/Operations-Add%20%7C%20Sub%20%7C%20Mul%20%7C%20Div-F59E0B?style=for-the-badge)
![FPGA](https://img.shields.io/badge/Target-Cyclone%20IV%20E-22C55E?style=for-the-badge)

This repository contains a configurable 32-bit floating point arithmetic unit (FPU) implemented in SystemVerilog. The design follows IEEE 754 single-precision format and supports the four fundamental arithmetic operations.

## Snapshot

| Item | Value |
|---|---|
| Precision | 32-bit IEEE 754 single precision |
| Sign / Exponent / Mantissa | 1 / 8 / 23 |
| Core operations | Addition, Subtraction, Multiplication, Division |
| Design approach | Module-based FSM pipeline |
| Validation | Simulation + FPGA implementation summary |

## IEEE 754 Coverage

The datapath uses standard single-precision fields:

- 1 sign bit
- 8 exponent bits
- 23 mantissa bits

Handled special classes and edge cases:

- Zero
- Infinity
- NaN
- Denormalized values
- Positive/negative sign combinations

## Architecture

Top-level orchestration is handled by fpu_sp_top.sv, which routes commands and operands to dedicated operation modules:

- fpu_sp_add.sv
- fpu_sp_sub.sv
- fpu_sp_mul.sv
- fpu_sp_div.sv

Command map:

| Command | Operation |
|---|---|
| 0001 | Addition |
| 0010 | Subtraction |
| 0011 | Multiplication |
| 0100 | Division |

Common floating-point processing stages:

1. Unpack fields
2. Align/process mantissas and exponents
3. Normalize
4. Round (round-to-nearest-even)
5. Pack result

## Module Highlights

### Addition: fpu_sp_add.sv

- Exponent alignment with shifted mantissa handling
- Guard/sticky-aware precision behavior
- Correct sign-aware effective add/subtract flow

### Subtraction: fpu_sp_sub.sv

- Sign inversion strategy over an add-style path
- Proper normalization and special-case handling

### Multiplication: fpu_sp_mul.sv

- 24x24 mantissa multiply path (48-bit intermediate)
- Exponent bias correction and sign XOR
- Guard/round/sticky extraction prior to packing

### Division: fpu_sp_div.sv

- Iterative non-restoring division style implementation
- Quotient/remainder tracking and exponent correction
- Divide-by-zero and infinity/NaN behavior support

## Verification Summary

Simulation was executed with testcases covering:

- Basic arithmetic correctness
- Sign combinations
- Zero, infinity, and NaN behavior
- Denormal and boundary-style inputs

Report-based outcome:

- All six SystemVerilog files compiled successfully
- Arithmetic modules produced expected outputs for standard and special-case tests
- One non-standard rounding discrepancy was noted for further refinement

## FPGA Implementation Summary

Target platform from report notes: Altera Cyclone IV E.

| Resource | Usage |
|---|---|
| Logic elements | 2,184 / 22,320 (~10%) |
| Registers | 1,013 |
| Embedded 9-bit multipliers | 7 / 132 (~5%) |
| Memory bits | 0 / 608,256 |
| Pins | 15 / 154 (~10%) |
| Max operating frequency | 100.72 MHz |
| Target clock | 50 MHz |

The timing margin indicates stable operation at target frequency with room for extensions.

## Key Project Assets

- Quartus project files: *.qpf, *.qsf, *.qws
- FPU RTL modules: fpu_sp_*.sv
- Qsys/IP integration files
- Simulation setup and artifacts
- Design report: DSD_Individual.pdf

## Build and Simulation Flow

1. Open the Quartus project file.
2. Compile the design.
3. Launch simulation from the provided simulation setup.
4. Run testbench cases and inspect logs/waveforms.

## Future Improvements

- Add IEEE 754 exception flags (overflow, underflow, invalid, inexact, divide-by-zero)
- Add additional IEEE rounding modes
- Add fused multiply-add (FMA)
- Reduce divide latency (for example SRT or Newton-Raphson variants)
- Extend to double precision support

## Author

Kopithan M  
University of Moratuwa  
Department of Electronic and Telecommunication Engineering
