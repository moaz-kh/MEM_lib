# MEM_lib — FPGA Memory Library

A SystemVerilog memory library with six XPM-compatible modules targeting the Lattice iCE40 UP5K. All modules are synthesisable with Yosys/NextPNR and validated with self-checking testbenches.

---

## Module Overview

| Module | Type | Ports | Sim | Synth Result |
|--------|------|-------|-----|-------------|
| `sprom` | Single Port ROM | 1R | 42/42 | LUT-ROM |
| `spram` | Single Port RAM | 1R/W | 78/78 | `1× SB_RAM40_4K` |
| `dprom` | Dual Port ROM | 2R | 222/222 | LUT-ROM |
| `dpram` | Dual Port RAM (common clk) | 1R/W + 1R/W | 67/67 | LUT-based |
| `dpdistram` | Dual Port Distributed RAM | 1R/W + 1R | 46/51 | `2× SB_RAM40_4K` |
| `tdpram` | True Dual Port RAM | 1R/W + 1R/W | WIP | — |

All dual-port modules share a single common clock (`clka`). No separate `clkb` — iCE40 block RAM is natively single-clock.

---

## Quick Start

### Prerequisites
```bash
sudo apt install iverilog gtkwave yosys nextpnr-ice40 fpga-icestorm
```

### Simulation
```bash
make sim TOP_MODULE=spram   TESTBENCH=spram_tb
make sim TOP_MODULE=sprom   TESTBENCH=sprom_tb
make sim TOP_MODULE=dpram   TESTBENCH=dpram_tb
make sim TOP_MODULE=dprom   TESTBENCH=dprom_tb
make sim TOP_MODULE=dpdistram TESTBENCH=dpdistram_tb
```

### Synthesis (iCE40)
```bash
make synth-ice40 TOP_MODULE=spram
make synth-ice40 TOP_MODULE=sprom   INIT_FILE=sources/mem/sprom_init.hex
make synth-ice40 TOP_MODULE=dpram
make synth-ice40 TOP_MODULE=dprom   INIT_FILE=sources/mem/dprom_init.hex
make synth-ice40 TOP_MODULE=dpdistram
```

### Waveforms
```bash
make waves TOP_MODULE=spram TESTBENCH=spram_tb
```

---

## Module Details

### sprom — Single Port ROM
XPM_MEMORY_SPROM compatible. ROM content loaded via `$readmemh`. Supports configurable read latency (0–4+), sync/async reset, and `regcea` pipeline control.

```systemverilog
sprom #(
    .ADDR_WIDTH_A(6),           // 64 locations
    .READ_DATA_WIDTH_A(32),
    .MEMORY_SIZE(2048),
    .READ_LATENCY_A(2),
    .MEMORY_INIT_FILE("sources/mem/sprom_init.hex")
) u_sprom ( .clka(clk), .addra(addr), .douta(data), ... );
```

### spram — Single Port RAM
XPM_MEMORY_SPRAM compatible. Byte-wide write enables (`wea` vector), configurable read latency, write modes (`read_first` / `write_first` / `no_change`), sync/async reset.

```systemverilog
spram #(
    .ADDR_WIDTH_A(6),
    .WRITE_DATA_WIDTH_A(32),
    .BYTE_WRITE_WIDTH_A(8),     // byte-enable granularity
    .READ_LATENCY_A(2)
) u_spram ( .clka(clk), .wea(byte_en), .addra(addr), .dina(wr_data), .douta(rd_data), ... );
```

### dprom — Dual Port ROM
Both ports read the shared ROM independently on the common clock. Useful for CPU dual-fetch (instruction + data), lookup tables, and microcode ROMs.

```systemverilog
dprom #(
    .ADDR_WIDTH_A(6), .ADDR_WIDTH_B(6),
    .READ_DATA_WIDTH_A(32), .READ_DATA_WIDTH_B(32),
    .MEMORY_INIT_FILE("sources/mem/dprom_init.hex")
) u_dprom ( .clka(clk), .addra(a), .douta(da), .addrb(b), .doutb(db), ... );
```

### dpram — Dual Port RAM
Both ports read and write the shared memory. Single `always_ff` block — Port B writes first (blocking), Port A writes second, so **Port A wins on same-address collision**. Supports `read_first`, `write_first`, `no_change` per port.

```systemverilog
dpram #(
    .DATA_WIDTH(32), .ADDR_WIDTH(8),
    .WRITE_MODE_A("read_first"), .WRITE_MODE_B("read_first")
) u_dpram ( .clka(clk), .ena(ena), .wea(wea), .addra(addra), ... );
```

### dpdistram — Dual Port Distributed RAM
XPM_MEMORY_DPDISTRAM compatible. Port A: read/write with byte-wide enables. Port B: read-only. Key differentiator: sub-word writes without read-modify-write cycles — ideal for cache line fills, packet processing, and processor store operations.

```systemverilog
dpdistram #(
    .ADDR_WIDTH_A(6), .MEMORY_SIZE(512),
    .WRITE_DATA_WIDTH_A(32), .BYTE_WRITE_WIDTH_A(8),
    .READ_LATENCY_A(1), .READ_LATENCY_B(1)
) u_dist ( .clka(clk), .wea(byte_en), .addra(wa), .dina(wd),
           .addrb(rb), .doutb(rd), ... );
```

### tdpram — True Dual Port RAM (WIP)
Both ports support independent read/write. RTL uses the same single `always_ff` collision-arbitration pattern as `dpram`. Testbench timing fix pending — see `TODO.md`.

---

## Project Structure

```
MEM_lib/
├── README.md
├── CLAUDE.md                       # Claude Code project guidance
├── TODO.md                         # Known pending work
├── Makefile                        # Build system
├── sources/
│   ├── rtl/
│   │   ├── sprom.sv
│   │   ├── spram.sv
│   │   ├── dprom.sv
│   │   ├── dpram.sv
│   │   ├── dpdistram.sv
│   │   └── tdpram.sv
│   ├── tb/
│   │   ├── sprom_tb.sv
│   │   ├── spram_tb.sv
│   │   ├── dprom_tb.sv
│   │   ├── dpram_tb.sv
│   │   ├── dpdistram_tb.sv
│   │   └── tdpram_tb.sv
│   ├── mem/
│   │   ├── sprom_init.hex          # 64×32-bit ROM init patterns
│   │   └── dprom_init.hex          # 64×32-bit ROM init patterns
│   ├── constraints/                # PCF constraint files
│   └── rtl_list.f                  # Auto-generated file list
├── sim/
│   ├── waves/                      # VCD waveform outputs
│   └── logs/                       # Simulation logs
└── backend/
    ├── synth/                      # Yosys JSON/netlist outputs
    ├── pnr/                        # NextPNR ASC outputs
    ├── bitstream/                  # Bitstream binaries
    └── reports/                    # Timing and utilisation reports
```

---

## Design Rules

- **Single common clock** — all modules use `clka` only; no `clkb`
- **Synchronous reset** — output registers reset synchronously by default (`RST_MODE = "SYNC"`)
- **No `ifdef SIMULATION` in ROM init** — synthesis path uses bare `$readmemh`; zero-init loop is simulation-only to prevent Yosys constant-folding the ROM
- **Blocking writes in `always_ff`** — enables write-priority ordering within a single clock block

## Tools

| Tool | Purpose |
|------|---------|
| Icarus Verilog (`iverilog`) | Simulation |
| GTKWave | Waveform viewing |
| Yosys | RTL synthesis |
| NextPNR (`nextpnr-ice40`) | Place & route |
| IceStorm (`icepack`, `icetime`) | Bitstream & timing |

## License

MIT License — Copyright (c) 2026 [moaz khaled](https://github.com/moaz-kh).

Free to use, modify, and distribute for any purpose. Attribution required — keep the copyright notice in all copies or substantial portions of the code.
