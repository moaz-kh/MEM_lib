# MEM_lib — Pending Work

## tdpram — Fix testbench timing (sim: 4/56)

**Root cause**: `write_port_b` task sets signals and calls `@(posedge clkb)` *after*
setting them, meaning the write fires on the very next edge with no setup time.
Port A and Port B reads then see 0x00000000 (unwritten memory).

**Fix needed in `sources/tb/tdpram_tb.sv`**:
- Align `write_port_b` with `write_port_a` style: wait for posedge FIRST,
  then set signals, then wait for a second posedge before clearing `web`.

```sv
// Current (broken):
task automatic write_port_b(...);
    enb = 1; web = 1;
    addrb = addr; dinb = data;
    @(posedge clkb);
    web = 0;
endtask

// Fix:
task automatic write_port_b(...);
    @(posedge clkb);       // align first
    enb = 1; web = 1;
    addrb = addr; dinb = data;
    @(posedge clkb);       // write clocked in
    web = 0;
endtask
```

After fix: run `make sim TOP_MODULE=tdpram TESTBENCH=tdpram_tb` → expect 56/56.

## tdpram — Synthesis (after sim passes)

```bash
make synth-ice40 TOP_MODULE=tdpram
```

Expected: LUT-based (ADDR_WIDTH_A=10 default is large, may get SB_RAM40_4K or LUTs).

## Commit dp* modules

Once tdpram sim+synth pass, commit all dp* changes together.
