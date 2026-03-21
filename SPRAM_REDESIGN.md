# SPRAM Module Redesign Documentation

## Overview
Complete redesign of `spram.sv` to match XPM_MEMORY_SPRAM specification while excluding ECC, sleep mode, UltraRAM features, and complex memory initialization.

## Design Goals
- XPM_MEMORY_SPRAM compatible interface with matching default values
- Professional byte-addressable single port RAM
- Clean memory initialization with synthesis control
- Industry-standard SystemVerilog implementation
- Drop-in replacement for XPM_MEMORY_SPRAM (minus excluded features)

## Parameter Changes

### Parameters Renamed (Old → New)
- `DATA_WIDTH` → `WRITE_DATA_WIDTH_A` / `READ_DATA_WIDTH_A`
- `ADDR_WIDTH` → `ADDR_WIDTH_A`
- `READ_LATENCY` → `READ_LATENCY_A`
- `WRITE_MODE` → `WRITE_MODE_A`
- `READ_RESET_VALUE` → `READ_RESET_VALUE_A`

### New Parameters Added
- `BYTE_WRITE_WIDTH_A` (default: 32) - Controls byte-wide write granularity
- `RST_MODE_A` (default: "SYNC") - Reset mode: "SYNC" or "ASYNC"
- `CASCADE_HEIGHT` (default: 0) - For compatibility (not used)
- `IGNORE_INIT_SYNTH` (default: 0) - Controls initialization in synthesis

### Parameters Removed
- `MEMORY_PRIMITIVE`, `AUTO_SLEEP_TIME`, `ECC_MODE`, `WAKEUP_TIME`
- `SIM_ASSERT_CHK`, `MESSAGE_CONTROL`, `MEMORY_OPTIMIZATION`
- `MEMORY_INIT_PARAM`, `USE_MEM_INIT`, `USE_MEM_INIT_MMI`

### XPM Default Values Applied
```systemverilog
parameter ADDR_WIDTH_A = 6,                    // XPM default: 6
parameter BYTE_WRITE_WIDTH_A = 32,             // XPM default: 32
parameter CASCADE_HEIGHT = 0,                  // XPM default: 0
parameter IGNORE_INIT_SYNTH = 0,               // XPM default: 0
parameter MEMORY_INIT_FILE = "none",           // XPM default: "none"
parameter MEMORY_SIZE = 2048,                  // XPM default: 2048
parameter READ_DATA_WIDTH_A = 32,              // XPM default: 32
parameter READ_LATENCY_A = 2,                  // XPM default: 2
parameter READ_RESET_VALUE_A = "0",            // XPM default: "0"
parameter RST_MODE_A = "SYNC",                 // XPM default: "SYNC"
parameter WRITE_DATA_WIDTH_A = 32,             // XPM default: 32
parameter WRITE_MODE_A = "read_first"          // XPM default: "read_first"
```

## Port Interface Changes

### Ports Added
- `regcea` - Register clock enable for output pipeline control
- `sbiterra` - Single bit error status (tied to 1'b0, no ECC)
- `dbiterra` - Double bit error status (tied to 1'b0, no ECC)

### Ports Modified
- `wea` - Changed from single bit to vector `[WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-1:0]`

### Ports Removed
- `sleep` - No sleep mode support
- `injectsbiterra` - No ECC support
- `injectdbiterra` - No ECC support

## Key Features Implemented

### 1. Byte-Wide Write Enable
- Vector `wea` with configurable width based on `BYTE_WRITE_WIDTH_A`
- Word-wide writes: `BYTE_WRITE_WIDTH_A = WRITE_DATA_WIDTH_A` → `wea[0]`
- Byte-wide writes: `BYTE_WRITE_WIDTH_A = 8` → `wea[3:0]` for 32-bit data
- Each bit in `wea` controls one byte of write data

### 2. Enhanced Read Latency Control
- `regcea` controls final output register stage
- Supports `READ_LATENCY_A` from 0 to 100
- Proper pipeline implementation for latency >2
- Matches XPM timing diagrams

### 3. Dual Reset Mode Support
- `RST_MODE_A = "SYNC"`: Synchronous reset (default)
- `RST_MODE_A = "ASYNC"`: Asynchronous reset
- Reset affects only output registers, preserves memory contents
- Uses `READ_RESET_VALUE_A` for reset value

### 4. Memory Initialization with Synthesis Control
**Priority:**
1. If `MEMORY_INIT_FILE != "none"` → use `$readmemh()`
2. Else → initialize to zeros

**IGNORE_INIT_SYNTH Control:**
- `IGNORE_INIT_SYNTH = 0`: Apply initialization to both simulation and synthesis
- `IGNORE_INIT_SYNTH = 1`: Apply initialization only to simulation

### 5. Write Mode Support
- `"read_first"`: Return old data during write cycle
- `"write_first"`: Return new data during write cycle
- `"no_change"`: Keep previous output during write

## Test Plan

### Testbench Coverage Matrix

#### Parameter Combinations
1. **Data Width Variations:**
   - 8-bit, 16-bit, 32-bit, 64-bit

2. **Address Width Variations:**
   - Small memory (ADDR_WIDTH_A = 4, depth = 16)
   - Medium memory (ADDR_WIDTH_A = 6, depth = 64, default)
   - Large memory (ADDR_WIDTH_A = 10, depth = 1024)

3. **Write Enable Configurations:**
   - Word-wide: `BYTE_WRITE_WIDTH_A = WRITE_DATA_WIDTH_A`
   - Byte-wide: `BYTE_WRITE_WIDTH_A = 8`
   - 9-bit byte-wide: `BYTE_WRITE_WIDTH_A = 9`

4. **Read Latency Variations:**
   - Combinational: `READ_LATENCY_A = 0`
   - Single registered: `READ_LATENCY_A = 1`
   - Double registered: `READ_LATENCY_A = 2` (default)
   - Pipelined: `READ_LATENCY_A = 3, 4, 5`

5. **Reset Mode Testing:**
   - Synchronous: `RST_MODE_A = "SYNC"`
   - Asynchronous: `RST_MODE_A = "ASYNC"`

6. **Write Mode Testing:**
   - `WRITE_MODE_A = "read_first"`
   - `WRITE_MODE_A = "write_first"`
   - `WRITE_MODE_A = "no_change"`

7. **Memory Initialization Testing:**
   - No initialization: `MEMORY_INIT_FILE = "none"`
   - File initialization: `MEMORY_INIT_FILE = "test_init.mem"`
   - Synthesis control: `IGNORE_INIT_SYNTH = 0/1`

#### Functional Tests
1. **Basic Read/Write Operations**
2. **Byte-Wide Write Testing**
3. **Pipeline Control (`regcea`) Testing**
4. **Reset Behavior Validation**
5. **Write Mode Timing Verification**
6. **Memory Initialization Verification**
7. **Address Boundary Testing**
8. **Data Pattern Testing**
9. **Random Access Testing**
10. **Stress Testing**

## Implementation Status
- [x] Plan documentation created
- [ ] Core module redesign
- [ ] Byte-wide write enable implementation
- [ ] Read latency pipeline control
- [ ] Reset mode implementation
- [ ] Memory initialization control
- [ ] Comprehensive testbench creation
- [ ] Full validation testing

## File Structure
```
MEM_lib/
├── SPRAM_REDESIGN.md          # This documentation
├── sources/rtl/spram.sv       # Redesigned SPRAM module
├── sources/tb/spram_tb.sv     # Comprehensive testbench
├── test_data/                 # Test memory initialization files
│   └── test_init.mem         # Sample initialization data
└── sim/                      # Simulation results
```

## Validation Criteria
- All parameter combinations must simulate successfully
- Timing behavior must match XPM specification
- Byte-wide writes must work correctly for all configurations
- Reset modes must behave as specified
- Memory initialization must work in both simulation and synthesis modes
- All write modes must produce correct timing
- Pipeline control must work for all read latencies