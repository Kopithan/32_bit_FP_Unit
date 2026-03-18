# 32-bit Floating Point Arithmetic Unit (IEEE 754 Single Precision)

This repository contains a configurable 32-bit floating point arithmetic unit (FPU) implemented in SystemVerilog. The design follows IEEE 754 single-precision format and supports the four core arithmetic operations:

- Addition
- Subtraction
- Multiplication
- Division

The implementation was developed for EN3021 Digital System Design and validated through simulation and FPGA synthesis.

## IEEE 754 Format

The datapath uses standard single precision fields:

- 1 sign bit
- 8 exponent bits
- 23 mantissa bits

The design handles special values and edge cases including:

- Zero
- Infinity
- NaN
- Denormalized values
- Sign combinations (+/-)

## Top-Level Architecture

The arithmetic unit is organized around a top-level controller that routes operands to operation-specific modules:

- `fpu_sp_add.sv`
- `fpu_sp_sub.sv`
- `fpu_sp_mul.sv`
- `fpu_sp_div.sv`
- `fpu_sp_top.sv`

A command interface selects operation mode:

- `0001`: Add
- `0010`: Subtract
- `0011`: Multiply
- `0100`: Divide

Each operation module is implemented as a finite state machine (FSM) and follows a staged floating-point flow:

1. Unpack fields
2. Align/process mantissas and exponents
3. Normalize
4. Round (round-to-nearest-even)
5. Pack output

## Module Notes

### Addition (`fpu_sp_add.sv`)

- Exponent alignment with shifted mantissa handling
- Guard/sticky-aware precision flow
- Handles effective add/subtract based on signs

### Subtraction (`fpu_sp_sub.sv`)

- Uses sign-inversion strategy with shared add-style processing
- Supports special-case behavior and normalization

### Multiplication (`fpu_sp_mul.sv`)

- 24x24 mantissa product path (48-bit intermediate)
- Exponent bias correction and sign XOR
- Guard/round/sticky extraction before packing

### Division (`fpu_sp_div.sv`)

- Iterative non-restoring division style flow
- Quotient/remainder tracking and exponent correction
- Divide-by-zero and infinity/NaN handling

## Verification Summary

Simulation was run with comprehensive testcases covering:

- Basic arithmetic correctness
- Sign combinations
- Zero, infinity, NaN behavior
- Denormal and boundary-style inputs

Observed outcome from report notes:

- All six SystemVerilog design/test files compiled successfully
- Arithmetic modules produced correct results for standard and special-case tests
- One non-standard rounding discrepancy was identified for future refinement

## FPGA Implementation (Report Summary)

Target platform in project report: Altera Cyclone IV E.

Reported synthesis/place-and-route highlights:

- Logic elements: 2,184 / 22,320 (~10%)
- Registers: 1,013
- Embedded 9-bit multipliers: 7 / 132 (~5%)
- Memory bits: 0 / 608,256
- Pins: 15 / 154 (~10%)
- Max operating frequency: 100.72 MHz
- Target operating clock: 50 MHz

This indicates comfortable timing margin and room for additional features.

## Project Files

Primary hardware and project files in this repo include:

- Quartus project files (`*.qpf`, `*.qsf`, `*.qws`)
- FPU RTL modules (`fpu_sp_*.sv`)
- Top-level and board integration files
- Qsys/IP integration files
- Simulation configuration and artifacts
- Report document (`DSD_Individual.pdf`)

## Build and Simulation

Typical Quartus/ModelSim flow:

1. Open the Quartus project file.
2. Compile the design.
3. Launch simulation using the provided simulation setup.
4. Run testbench cases and inspect result waveforms/logs.

## Future Improvements

Based on report discussion:

- Add IEEE 754 exception flags (overflow, underflow, invalid, inexact, divide-by-zero)
- Add support for additional rounding modes
- Add fused multiply-add (FMA)
- Optimize divide latency (for example SRT/Newton-Raphson variants)
- Extend to double precision

## Author

Kopithan M  
University of Moratuwa  
Department of Electronic and Telecommunication Engineering
