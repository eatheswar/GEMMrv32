# GEMMrv32 RISC-V Processor

[![datasheet (pdf)](https://img.shields.io/badge/Data%20Sheet-PDF-ffbd00?longCache=true&style=flat&logo=asciidoctor&colorA=273274)](https://github.com/stnolting/neorv32/releases/download/nightly_release/NEORV32-nightly.pdf)
[![datasheet (html)](https://img.shields.io/badge/-HTML-ffbd00?longCache=true&style=flat)](https://stnolting.github.io/neorv32)
[![userguide (pdf)](https://img.shields.io/badge/User%20Guide-PDF-ffbd00?longCache=true&style=flat&logo=asciidoctor&colorA=273274)](https://github.com/stnolting/neorv32/releases/download/nightly_release/NEORV32_UserGuide-nightly.pdf)
[![userguide (html)](https://img.shields.io/badge/-HTML-ffbd00?longCache=true&style=flat)](https://stnolting.github.io/neorv32/ug)
[![license](https://img.shields.io/github/license/stnolting/neorv32?label=License&style=flat&logo=bsd)](https://github.com/stnolting/neorv32/blob/main/LICENSE)

GEMMrv32 is a customized RISC-V processor platform based on the
[NEORV32](https://github.com/stnolting/neorv32) processor, extended with a dedicated
8×8 systolic-array GEMM (General Matrix Multiplication) accelerator.

The project explores hardware/software co-design by combining a programmable
32-bit RISC-V processor with a spatially parallel matrix-computation engine.
The accelerator is integrated through the NEORV32 Custom Functions Subsystem (CFS)
and is designed to offload computationally intensive matrix operations from the
CPU.

The complete project is available at:

**https://github.com/eatheswar/GEMMrv32**

---

## Project Overview

GEMMrv32 retains the highly configurable, platform-independent VHDL architecture
of NEORV32 while adding a custom hardware acceleration subsystem targeted at
matrix multiplication workloads.

The primary objective is to investigate the performance benefits of spatial
hardware acceleration compared with conventional sequential execution on a
32-bit embedded RISC-V processor.

Key areas of the project include:

- 32-bit RISC-V processor architecture
- Platform-independent VHDL implementation
- Configurable processor and SoC components
- Custom Functions Subsystem (CFS)
- Dedicated 8×8 systolic-array GEMM accelerator
- Hardware/software co-design
- C-based accelerator benchmarking
- RISC-V GCC software toolchain integration
- Cycle-accurate simulation using GHDL
- Comparative CPU versus hardware-accelerator evaluation

---

## GEMM Accelerator

GEMMrv32 integrates an 8×8 systolic-array matrix multiplication accelerator
through the NEORV32 Custom Functions Subsystem.

The accelerator contains 64 parallel processing elements and uses local
data reuse to perform matrix multiplication spatially rather than executing
individual multiply-accumulate operations sequentially on the CPU.

Matrix operations larger than 8×8 are handled using tiled computation.

The current implementation uses local ping-pong registers for 8×8 matrix
blocks, allowing loaded data to be reused across the processing elements.

The accelerator is accessible from software running on the RISC-V processor,
allowing conventional C programs to offload matrix multiplication to hardware.

---

## Performance

The accelerator was benchmarked against native C implementations executing
directly on the NEORV32 RISC-V CPU.

All benchmark inputs use dynamically generated randomized matrices to avoid
results being biased by trivial zero-value inputs.

### Dimension Sweep

The first benchmark compares matrix sizes while using an
`rv32im_zicsr_zifencei` CPU configuration with hardware multiplication and
`-Os` compiler optimization.

| Matrix Dimension | MAC Operations | CPU Cycles | Accelerator Cycles | Speedup |
|:----------------:|---------------:|-----------:|-------------------:|--------:|
| 8×8              | 512            | 17,030     | 517                | **32×** |
| 16×16            | 4,096          | 128,822    | 2,543              | **50×** |
| 24×24            | 13,824         | 427,646    | 7,261              | **58×** |

The increasing speedup with matrix size demonstrates the advantage of spatial
parallelism and local data reuse over sequential CPU execution.

---

## Optimized CPU Comparison

A second benchmark was performed using a more aggressively optimized CPU
baseline.

The CPU was configured as:

`rv32imc_zba_zbb_zbs_zicsr_zifencei`

and compiled using `-O3` with loop unrolling (`#pragma GCC unroll 16`).

The comparison was performed using a 16×16 matrix.

| Architecture | Execution Cycles | Relative Speed |
|:-------------|-----------------:|---------------:|
| CPU (`-Os`) | 128,822 | 1× |
| CPU (`-O3` + unrolling) | 66,198 | 1× |
| GEMM Accelerator | 2,527 | **26.2× faster than optimized CPU** |

Compiler optimization reduced the CPU execution time by approximately half,
demonstrating that the accelerator advantage remains even against a strongly
optimized software implementation.

The hardware accelerator achieves a **26.2× speedup over the optimized CPU
baseline** for the 16×16 workload.

---

## Accelerator Utilization

The current implementation is limited by the 32-bit Wishbone-based memory
interface connecting the accelerator to the processor system.

For the measured implementation, the accelerator achieves approximately:

- **1.62 MACs/cycle effective throughput**
- **64 MACs/cycle theoretical PE throughput**
- 64 parallel processing elements

Therefore, the current implementation uses only a fraction of the theoretical
compute throughput of the systolic array.

This makes the interconnect and data-delivery mechanism an important area for
future optimization.

Potential improvements include:

- Wider data paths
- Dedicated DMA transfers
- Improved matrix tiling
- Larger local buffers
- Streaming data interfaces
- Improved accelerator/CPU decoupling
- Reduced configuration and transfer overhead

---

## Software

GEMMrv32 programs can be written in C and compiled using the RISC-V GCC
toolchain before being executed on the processor in simulation or FPGA
implementations.

The benchmark software compares equivalent matrix multiplication workloads
between:

1. Native CPU execution
2. Hardware-accelerated GEMM execution

This allows accelerator performance to be evaluated using the same processor
environment and software workload.

---

## NEORV32 Foundation

GEMMrv32 is built upon the NEORV32 processor framework.

NEORV32 provides a customizable microcontroller-like RISC-V SoC implemented
entirely in platform-independent VHDL.

It provides:

- CPU + SoC + software framework
- RV32 RISC-V architecture
- Configurable ISA extensions
- Instruction and data memories
- Optional instruction/data caches
- Wishbone-compatible external bus
- AXI4-compatible bridge
- AXI4-Stream-compatible interface
- DMA controller
- Custom Functions Subsystem (CFS)
- GPIO, UART, SPI, I²C and other peripherals
- Timers and counters
- SD-card support
- On-chip debugger
- RISC-V trace interface
- FreeRTOS and Zephyr support
- Experimental Linux support
- GHDL and FPGA/ASIC compatible VHDL implementation

For complete NEORV32 documentation, see:

- [NEORV32 Documentation](https://stnolting.github.io/neorv32/)
- [NEORV32 User Guide](https://stnolting.github.io/neorv32/ug/)
- [NEORV32 GitHub Repository](https://github.com/stnolting/neorv32)

---

## Research Direction

GEMMrv32 serves as a platform for investigating hardware/software
co-design and specialized processor architectures.

The current GEMM accelerator provides a baseline for studying:

- Spatial versus sequential computation
- CPU/accelerator workload partitioning
- Memory bandwidth limitations
- Systolic-array architectures
- Accelerator instruction and control interfaces
- DMA-based accelerator data movement
- Custom processor architectures
- Domain-specific acceleration
- Compiler-assisted hardware acceleration

Future versions may explore additional accelerator architectures, improved
memory subsystems, custom processor extensions, and alternative CPU/accelerator
interfaces.

---

## Project Status

The current implementation includes:

- [x] NEORV32-based RISC-V processor
- [x] Custom 8×8 systolic-array GEMM accelerator
- [x] 64 parallel processing elements
- [x] Tiled matrix multiplication
- [x] C benchmark implementation
- [x] RISC-V GCC compilation
- [x] GHDL simulation
- [x] Randomized benchmark inputs
- [x] CPU versus accelerator cycle comparison
- [x] Optimized CPU baseline
- [x] Performance characterization

---


## Contributing

Contributions are very welcome! If you'd like to improve something, fix a bug,
add a feature, improve documentation, or extend the GEMM accelerator, feel free
to open an issue or submit a pull request.

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

A big **thank you** to everyone who contributes to GEMMrv32 and helps improve
the project!

<a href="https://github.com/eatheswar/GEMMrv32/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=eatheswar/GEMMrv32" />
</a>

### Upstream

GEMMrv32 is based on the [NEORV32](https://github.com/stnolting/neorv32)
processor framework by Stephan Nolting and the NEORV32 community.

We gratefully acknowledge the upstream project's architecture, documentation,
tooling, and contributions that make this work possible.



## License

GEMMrv32 is based on the open-source NEORV32 project.

See the repository license and the upstream
[NEORV32 license](https://github.com/stnolting/neorv32/blob/main/LICENSE)
for licensing information.