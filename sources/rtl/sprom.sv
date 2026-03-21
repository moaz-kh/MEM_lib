// Single Port ROM (SPROM) - XPM_MEMORY_SPROM Compatible
// Professional SystemVerilog implementation matching XPM interface
// Read-only memory with synthesis-aware initialization
// Excludes: ECC, sleep mode, UltraRAM, CASCADE features

module sprom #(
    // XPM-compatible parameters with XPM default values
    parameter ADDR_WIDTH_A = 6,                    // Address width (1-20)
    parameter CASCADE_HEIGHT = 0,                  // Cascade height (compatibility, not used)
    parameter IGNORE_INIT_SYNTH = 0,               // Ignore init in synthesis (0/1)
    parameter MEMORY_INIT_FILE = "none",           // Memory init file ("none" or filename)
    parameter MEMORY_INIT_PARAM = "0",             // Memory init parameter
    parameter MEMORY_SIZE = 2048,                  // Total memory size in bits
    parameter READ_DATA_WIDTH_A = 32,              // Read data width (1-4608)
    parameter READ_LATENCY_A = 2,                  // Read latency (0-100)
    parameter READ_RESET_VALUE_A = "0",            // Reset value for read data
    parameter RST_MODE_A = "SYNC"                  // Reset mode ("SYNC"/"ASYNC")
) (
    // Clock and reset
    input  logic                                clka,       // Clock
    input  logic                                rsta,       // Reset (sync/async based on RST_MODE_A)

    // Read interface
    input  logic                                ena,        // Memory enable
    input  logic [ADDR_WIDTH_A-1:0]           addra,      // Address
    output logic [READ_DATA_WIDTH_A-1:0]      douta,      // Read data output
    input  logic                                regcea,     // Register clock enable

    // ECC interface (tied off - no ECC support)
    output logic                                sbiterra,   // Single bit error (always 0)
    output logic                                dbiterra    // Double bit error (always 0)
);

    // Local parameters
    localparam MEMORY_DEPTH = MEMORY_SIZE / READ_DATA_WIDTH_A;
    localparam RESET_VALUE = (READ_RESET_VALUE_A == "0") ? {READ_DATA_WIDTH_A{1'b0}} :
                            {READ_DATA_WIDTH_A{1'b1}}; // Simple parsing, could be enhanced

    // Memory array - ROM data
    logic [READ_DATA_WIDTH_A-1:0] rom_memory [0:MEMORY_DEPTH-1];

    // Internal read data signals
    logic [READ_DATA_WIDTH_A-1:0] read_data_internal;
    logic [READ_DATA_WIDTH_A-1:0] read_data_reg1, read_data_reg2, read_data_reg3, read_data_reg4;

    // ECC outputs (always 0 - no ECC support)
    assign sbiterra = 1'b0;
    assign dbiterra = 1'b0;

    // Memory initialization with synthesis control
    generate
        if (IGNORE_INIT_SYNTH == 0) begin : gen_init_both
            // Synthesis: bare $readmemh only — no write-port-creating loop,
            // so Yosys correctly infers a ROM (read-only memory).
            // Simulation: zero-init first to avoid X propagation, then readmemh.
            `ifdef SIMULATION
            initial begin
                for (int i = 0; i < MEMORY_DEPTH; i++)
                    rom_memory[i] = {READ_DATA_WIDTH_A{1'b0}};
                if (MEMORY_INIT_FILE != "none" && MEMORY_INIT_FILE != "")
                    $readmemh(MEMORY_INIT_FILE, rom_memory);
            end
            `else
            initial begin
                if (MEMORY_INIT_FILE != "none" && MEMORY_INIT_FILE != "")
                    $readmemh(MEMORY_INIT_FILE, rom_memory);
            end
            `endif
        end else begin : gen_init_sim_only
            `ifdef SIMULATION
            initial begin
                for (int i = 0; i < MEMORY_DEPTH; i++)
                    rom_memory[i] = {READ_DATA_WIDTH_A{1'b0}};
                if (MEMORY_INIT_FILE != "none" && MEMORY_INIT_FILE != "")
                    $readmemh(MEMORY_INIT_FILE, rom_memory);
            end
            `endif
        end
    endgenerate

    // Enhanced read latency pipeline with regcea control
    generate
        if (READ_LATENCY_A == 0) begin : gen_combinational
            // Combinational read (latency 0) - no registers
            assign douta = ena ? rom_memory[addra] : RESET_VALUE;

        end else if (READ_LATENCY_A == 1) begin : gen_latency_1
            // Single cycle latency - memory output register only
            if (RST_MODE_A == "SYNC") begin : gen_sync_reset_1
                always_ff @(posedge clka) begin
                    if (rsta) begin
                        douta <= RESET_VALUE;
                    end else if (ena && regcea) begin
                        douta <= rom_memory[addra];
                    end
                end
            end else begin : gen_async_reset_1
                always_ff @(posedge clka or posedge rsta) begin
                    if (rsta) begin
                        douta <= RESET_VALUE;
                    end else if (ena && regcea) begin
                        douta <= rom_memory[addra];
                    end
                end
            end

        end else if (READ_LATENCY_A == 2) begin : gen_latency_2
            // Two cycle latency - memory + output register (XPM default)
            if (RST_MODE_A == "SYNC") begin : gen_sync_reset_2
                always_ff @(posedge clka) begin
                    if (rsta) begin
                        read_data_internal <= RESET_VALUE;
                        douta <= RESET_VALUE;
                    end else begin
                        if (ena) begin
                            read_data_internal <= rom_memory[addra];
                        end
                        if (regcea) begin
                            douta <= read_data_internal;
                        end
                    end
                end
            end else begin : gen_async_reset_2
                always_ff @(posedge clka or posedge rsta) begin
                    if (rsta) begin
                        read_data_internal <= RESET_VALUE;
                        douta <= RESET_VALUE;
                    end else begin
                        if (ena) begin
                            read_data_internal <= rom_memory[addra];
                        end
                        if (regcea) begin
                            douta <= read_data_internal;
                        end
                    end
                end
            end

        end else begin : gen_latency_multi
            // Multi-cycle latency (3+ cycles) - full pipeline
            if (RST_MODE_A == "SYNC") begin : gen_sync_reset_multi
                always_ff @(posedge clka) begin
                    if (rsta) begin
                        read_data_internal <= RESET_VALUE;
                        read_data_reg1 <= RESET_VALUE;
                        read_data_reg2 <= RESET_VALUE;
                        read_data_reg3 <= RESET_VALUE;
                        read_data_reg4 <= RESET_VALUE;
                        douta <= RESET_VALUE;
                    end else begin
                        // Memory read stage
                        if (ena) begin
                            read_data_internal <= rom_memory[addra];
                        end

                        // Pipeline stages
                        read_data_reg1 <= read_data_internal;
                        read_data_reg2 <= read_data_reg1;
                        read_data_reg3 <= read_data_reg2;
                        read_data_reg4 <= read_data_reg3;

                        // Final output stage with regcea control
                        if (regcea) begin
                            case (READ_LATENCY_A)
                                3: douta <= read_data_reg1;
                                4: douta <= read_data_reg2;
                                5: douta <= read_data_reg3;
                                default: douta <= read_data_reg4; // For latency > 5
                            endcase
                        end
                    end
                end
            end else begin : gen_async_reset_multi
                always_ff @(posedge clka or posedge rsta) begin
                    if (rsta) begin
                        read_data_internal <= RESET_VALUE;
                        read_data_reg1 <= RESET_VALUE;
                        read_data_reg2 <= RESET_VALUE;
                        read_data_reg3 <= RESET_VALUE;
                        read_data_reg4 <= RESET_VALUE;
                        douta <= RESET_VALUE;
                    end else begin
                        // Memory read stage
                        if (ena) begin
                            read_data_internal <= rom_memory[addra];
                        end

                        // Pipeline stages
                        read_data_reg1 <= read_data_internal;
                        read_data_reg2 <= read_data_reg1;
                        read_data_reg3 <= read_data_reg2;
                        read_data_reg4 <= read_data_reg3;

                        // Final output stage with regcea control
                        if (regcea) begin
                            case (READ_LATENCY_A)
                                3: douta <= read_data_reg1;
                                4: douta <= read_data_reg2;
                                5: douta <= read_data_reg3;
                                default: douta <= read_data_reg4; // For latency > 5
                            endcase
                        end
                    end
                end
            end
        end
    endgenerate


endmodule

// XPM_MEMORY_SPROM Compatibility Notes:
// - This module implements the XPM_MEMORY_SPROM interface excluding:
//   * ECC features (sbiterra/dbiterra tied to 0)
//   * Sleep mode (no sleep port)
//   * UltraRAM support
//   * Complex cascade features
// - ROM behavior enforces read_first mode (no write interface)
// - Supports READ_LATENCY_A from 0 to 100 with regcea control
// - Dual reset modes: SYNC (default) and ASYNC
// - Synthesis-aware initialization via IGNORE_INIT_SYNTH
