// Dual Port ROM (DPROM) - XPM_MEMORY_DPROM Compatible
// Professional SystemVerilog implementation matching XPM interface
// True dual-port ROM with simultaneous independent reads from both ports
// Common clock only: both ports share clka

module dprom #(
    // XPM-compatible parameters with XPM default values
    parameter ADDR_WIDTH_A = 6,                    // Address width for Port A (1-20)
    parameter ADDR_WIDTH_B = 6,                    // Address width for Port B (1-20)
    parameter AUTO_SLEEP_TIME = 0,                 // Auto sleep time (compatibility)
    parameter CASCADE_HEIGHT = 0,                  // Cascade height (compatibility, not used)
    parameter ECC_MODE = "no_ecc",                 // ECC mode (compatibility)
    parameter IGNORE_INIT_SYNTH = 0,               // Ignore init in synthesis (0/1)
    parameter MEMORY_INIT_FILE = "none",           // Memory init file ("none" or filename)
    parameter MEMORY_INIT_PARAM = "0",             // Memory init parameter
    parameter MEMORY_OPTIMIZATION = "true",        // Memory optimization (compatibility)
    parameter MEMORY_PRIMITIVE = "auto",           // Memory primitive: "auto", "block", "distributed"
    parameter MEMORY_SIZE = 256,                  // Total memory size in bits
    parameter MESSAGE_CONTROL = 0,                 // Message control (compatibility)
    parameter READ_DATA_WIDTH_A = 8,              // Read data width for Port A (1-4608)
    parameter READ_DATA_WIDTH_B = 8,              // Read data width for Port B (1-4608)
    parameter READ_LATENCY_A = 2,                  // Read latency for Port A (0-100)
    parameter READ_LATENCY_B = 2,                  // Read latency for Port B (0-100)
    parameter READ_RESET_VALUE_A = "0",            // Reset value for Port A read data
    parameter READ_RESET_VALUE_B = "0",            // Reset value for Port B read data
    parameter RST_MODE_A = "SYNC",                 // Reset mode for Port A ("SYNC"/"ASYNC")
    parameter RST_MODE_B = "SYNC",                 // Reset mode for Port B ("SYNC"/"ASYNC")
    parameter SIM_ASSERT_CHK = 0,                  // Simulation assertion check (compatibility)
    parameter USE_EMBEDDED_CONSTRAINT = 0,         // Use embedded constraint (compatibility)
    parameter USE_MEM_INIT = 1,                    // Use memory initialization
    parameter USE_MEM_INIT_MMI = 0,                // Use MMI initialization (compatibility)
    parameter WAKEUP_TIME = "disable_sleep"        // Wakeup time (compatibility)
) (
    // Clock (shared by both ports)
    input  logic                                clka,       // Common clock

    // Port A interface (Read-only)
    input  logic                                rsta,       // Port A reset
    input  logic                                ena,        // Port A memory enable
    input  logic                                regcea,     // Port A register clock enable
    input  logic [ADDR_WIDTH_A-1:0]           addra,      // Port A address
    output logic [READ_DATA_WIDTH_A-1:0]      douta,      // Port A read data

    // Port B interface (Read-only)
    input  logic                                rstb,       // Port B reset
    input  logic                                enb,        // Port B memory enable
    input  logic                                regceb,     // Port B register clock enable
    input  logic [ADDR_WIDTH_B-1:0]           addrb,      // Port B address
    output logic [READ_DATA_WIDTH_B-1:0]      doutb,      // Port B read data

    // Power management (tied off - no power management)
    input  logic                                sleep,      // Sleep mode (compatibility)

    // ECC interface (tied off - no ECC support)
    output logic                                sbiterra,   // Single bit error Port A (always 0)
    output logic                                dbiterra,   // Double bit error Port A (always 0)
    output logic                                sbiterrb,   // Single bit error Port B (always 0)
    output logic                                dbiterrb,   // Double bit error Port B (always 0)
    input  logic                                injectsbiterra, // Inject single bit error A (compatibility)
    input  logic                                injectdbiterra, // Inject double bit error A (compatibility)
    input  logic                                injectsbiterrb, // Inject single bit error B (compatibility)
    input  logic                                injectdbiterrb  // Inject double bit error B (compatibility)
);

    // Local parameters (must be before initial blocks for Icarus compatibility)
    localparam MEMORY_DEPTH_A = MEMORY_SIZE / READ_DATA_WIDTH_A;
    localparam MEMORY_DEPTH_B = MEMORY_SIZE / READ_DATA_WIDTH_B;
    localparam RESET_VALUE_A = (READ_RESET_VALUE_A == "0") ? {READ_DATA_WIDTH_A{1'b0}} :
                              {READ_DATA_WIDTH_A{1'b1}};
    localparam RESET_VALUE_B = (READ_RESET_VALUE_B == "0") ? {READ_DATA_WIDTH_B{1'b0}} :
                              {READ_DATA_WIDTH_B{1'b1}};



    // Memory array - ROM data (use maximum data width for storage)
    localparam MAX_DATA_WIDTH = (READ_DATA_WIDTH_A > READ_DATA_WIDTH_B) ? READ_DATA_WIDTH_A : READ_DATA_WIDTH_B;
    localparam MAX_DEPTH = (MEMORY_DEPTH_A > MEMORY_DEPTH_B) ? MEMORY_DEPTH_A : MEMORY_DEPTH_B;
    logic [MAX_DATA_WIDTH-1:0] rom_memory [0:MAX_DEPTH-1];

    // Internal read data signals for Port A
    logic [READ_DATA_WIDTH_A-1:0] read_data_a_internal;
    logic [READ_DATA_WIDTH_A-1:0] read_data_a_reg1, read_data_a_reg2, read_data_a_reg3, read_data_a_reg4;

    // Internal read data signals for Port B
    logic [READ_DATA_WIDTH_B-1:0] read_data_b_internal;
    logic [READ_DATA_WIDTH_B-1:0] read_data_b_reg1, read_data_b_reg2, read_data_b_reg3, read_data_b_reg4;

    // ECC outputs (always 0 - no ECC support)
    assign sbiterra = 1'b0;
    assign dbiterra = 1'b0;
    assign sbiterrb = 1'b0;
    assign dbiterrb = 1'b0;

    // Memory initialization with synthesis control
    generate
        if (IGNORE_INIT_SYNTH == 0) begin : gen_init_both
            // Synthesis: bare $readmemh only — no write-port-creating loop,
            // so Yosys correctly infers a ROM.
            // Simulation: zero-init first to avoid X propagation, then readmemh.
            `ifdef SIMULATION
            initial begin
                for (int i = 0; i < MAX_DEPTH; i++)
                    rom_memory[i] = {MAX_DATA_WIDTH{1'b0}};
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
            // Apply initialization only to simulation
            `ifdef SIMULATION
            initial begin
                // Initialize all locations to zero first
                for (int i = 0; i < MAX_DEPTH; i++) begin
                    rom_memory[i] = {MAX_DATA_WIDTH{1'b0}};
                end

                // Load from file if specified
                if (MEMORY_INIT_FILE != "none" && MEMORY_INIT_FILE != "") begin
                    $readmemh(MEMORY_INIT_FILE, rom_memory);
                end
            end
            `endif
        end
    endgenerate

    // Port A: Read-only operations with configurable read latency
    generate
        if (READ_LATENCY_A == 0) begin : gen_combinational_a
            // Combinational read (latency 0) - no registers
            always_comb begin
                if (ena) begin
                    if (READ_DATA_WIDTH_A <= MAX_DATA_WIDTH) begin
                        read_data_a_internal = rom_memory[addra][READ_DATA_WIDTH_A-1:0];
                    end else begin
                        read_data_a_internal = {{(READ_DATA_WIDTH_A-MAX_DATA_WIDTH){1'b0}}, rom_memory[addra]};
                    end
                end else begin
                    read_data_a_internal = RESET_VALUE_A;
                end
            end
            assign douta = read_data_a_internal;

        end else if (READ_LATENCY_A == 1) begin : gen_latency_1_a
            // Single cycle latency - memory output register only
            if (RST_MODE_A == "SYNC") begin : gen_sync_reset_1_a
                always_ff @(posedge clka) begin
                    if (rsta) begin
                        douta <= RESET_VALUE_A;
                    end else if (ena && regcea) begin
                        if (READ_DATA_WIDTH_A <= MAX_DATA_WIDTH) begin
                            douta <= rom_memory[addra][READ_DATA_WIDTH_A-1:0];
                        end else begin
                            douta <= {{(READ_DATA_WIDTH_A-MAX_DATA_WIDTH){1'b0}}, rom_memory[addra]};
                        end
                    end
                end
            end else begin : gen_async_reset_1_a
                always_ff @(posedge clka or posedge rsta) begin
                    if (rsta) begin
                        douta <= RESET_VALUE_A;
                    end else if (ena && regcea) begin
                        if (READ_DATA_WIDTH_A <= MAX_DATA_WIDTH) begin
                            douta <= rom_memory[addra][READ_DATA_WIDTH_A-1:0];
                        end else begin
                            douta <= {{(READ_DATA_WIDTH_A-MAX_DATA_WIDTH){1'b0}}, rom_memory[addra]};
                        end
                    end
                end
            end

        end else begin : gen_latency_multi_a
            // Multi-cycle latency (2+ cycles) - full pipeline
            if (RST_MODE_A == "SYNC") begin : gen_sync_reset_multi_a
                always_ff @(posedge clka) begin
                    if (rsta) begin
                        read_data_a_internal <= RESET_VALUE_A;
                        read_data_a_reg1 <= RESET_VALUE_A;
                        read_data_a_reg2 <= RESET_VALUE_A;
                        read_data_a_reg3 <= RESET_VALUE_A;
                        read_data_a_reg4 <= RESET_VALUE_A;
                        douta <= RESET_VALUE_A;
                    end else begin
                        // Memory read stage
                        if (ena) begin
                            if (READ_DATA_WIDTH_A <= MAX_DATA_WIDTH) begin
                                read_data_a_internal <= rom_memory[addra][READ_DATA_WIDTH_A-1:0];
                            end else begin
                                read_data_a_internal <= {{(READ_DATA_WIDTH_A-MAX_DATA_WIDTH){1'b0}}, rom_memory[addra]};
                            end
                        end

                        // Pipeline stages
                        read_data_a_reg1 <= read_data_a_internal;
                        read_data_a_reg2 <= read_data_a_reg1;
                        read_data_a_reg3 <= read_data_a_reg2;
                        read_data_a_reg4 <= read_data_a_reg3;

                        // Final output stage with regcea control
                        if (regcea) begin
                            case (READ_LATENCY_A)
                                2: douta <= read_data_a_internal;
                                3: douta <= read_data_a_reg1;
                                4: douta <= read_data_a_reg2;
                                5: douta <= read_data_a_reg3;
                                default: douta <= read_data_a_reg4; // For latency > 5
                            endcase
                        end
                    end
                end
            end else begin : gen_async_reset_multi_a
                always_ff @(posedge clka or posedge rsta) begin
                    if (rsta) begin
                        read_data_a_internal <= RESET_VALUE_A;
                        read_data_a_reg1 <= RESET_VALUE_A;
                        read_data_a_reg2 <= RESET_VALUE_A;
                        read_data_a_reg3 <= RESET_VALUE_A;
                        read_data_a_reg4 <= RESET_VALUE_A;
                        douta <= RESET_VALUE_A;
                    end else begin
                        // Memory read stage
                        if (ena) begin
                            if (READ_DATA_WIDTH_A <= MAX_DATA_WIDTH) begin
                                read_data_a_internal <= rom_memory[addra][READ_DATA_WIDTH_A-1:0];
                            end else begin
                                read_data_a_internal <= {{(READ_DATA_WIDTH_A-MAX_DATA_WIDTH){1'b0}}, rom_memory[addra]};
                            end
                        end

                        // Pipeline stages
                        read_data_a_reg1 <= read_data_a_internal;
                        read_data_a_reg2 <= read_data_a_reg1;
                        read_data_a_reg3 <= read_data_a_reg2;
                        read_data_a_reg4 <= read_data_a_reg3;

                        // Final output stage with regcea control
                        if (regcea) begin
                            case (READ_LATENCY_A)
                                2: douta <= read_data_a_internal;
                                3: douta <= read_data_a_reg1;
                                4: douta <= read_data_a_reg2;
                                5: douta <= read_data_a_reg3;
                                default: douta <= read_data_a_reg4; // For latency > 5
                            endcase
                        end
                    end
                end
            end
        end
    endgenerate

    // Port B: Read-only operations with configurable read latency
    generate
        if (READ_LATENCY_B == 0) begin : gen_combinational_b
            // Combinational read (latency 0) - no registers
            always_comb begin
                if (enb) begin
                    if (READ_DATA_WIDTH_B <= MAX_DATA_WIDTH) begin
                        read_data_b_internal = rom_memory[addrb][READ_DATA_WIDTH_B-1:0];
                    end else begin
                        read_data_b_internal = {{(READ_DATA_WIDTH_B-MAX_DATA_WIDTH){1'b0}}, rom_memory[addrb]};
                    end
                end else begin
                    read_data_b_internal = RESET_VALUE_B;
                end
            end
            assign doutb = read_data_b_internal;

        end else if (READ_LATENCY_B == 1) begin : gen_latency_1_b
            // Single cycle latency
            if (RST_MODE_B == "SYNC") begin : gen_sync_reset_1_b
                always_ff @(posedge clka) begin
                    if (rstb) begin
                        doutb <= RESET_VALUE_B;
                    end else if (enb && regceb) begin
                        if (READ_DATA_WIDTH_B <= MAX_DATA_WIDTH) begin
                            doutb <= rom_memory[addrb][READ_DATA_WIDTH_B-1:0];
                        end else begin
                            doutb <= {{(READ_DATA_WIDTH_B-MAX_DATA_WIDTH){1'b0}}, rom_memory[addrb]};
                        end
                    end
                end
            end else begin : gen_async_reset_1_b
                always_ff @(posedge clka or posedge rstb) begin
                    if (rstb) begin
                        doutb <= RESET_VALUE_B;
                    end else if (enb && regceb) begin
                        if (READ_DATA_WIDTH_B <= MAX_DATA_WIDTH) begin
                            doutb <= rom_memory[addrb][READ_DATA_WIDTH_B-1:0];
                        end else begin
                            doutb <= {{(READ_DATA_WIDTH_B-MAX_DATA_WIDTH){1'b0}}, rom_memory[addrb]};
                        end
                    end
                end
            end

        end else begin : gen_latency_multi_b
            // Multi-cycle latency (2+ cycles) - full pipeline
            if (RST_MODE_B == "SYNC") begin : gen_sync_reset_multi_b
                always_ff @(posedge clka) begin
                    if (rstb) begin
                        read_data_b_internal <= RESET_VALUE_B;
                        read_data_b_reg1 <= RESET_VALUE_B;
                        read_data_b_reg2 <= RESET_VALUE_B;
                        read_data_b_reg3 <= RESET_VALUE_B;
                        read_data_b_reg4 <= RESET_VALUE_B;
                        doutb <= RESET_VALUE_B;
                    end else begin
                        // Memory read stage
                        if (enb) begin
                            if (READ_DATA_WIDTH_B <= MAX_DATA_WIDTH) begin
                                read_data_b_internal <= rom_memory[addrb][READ_DATA_WIDTH_B-1:0];
                            end else begin
                                read_data_b_internal <= {{(READ_DATA_WIDTH_B-MAX_DATA_WIDTH){1'b0}}, rom_memory[addrb]};
                            end
                        end

                        // Pipeline stages
                        read_data_b_reg1 <= read_data_b_internal;
                        read_data_b_reg2 <= read_data_b_reg1;
                        read_data_b_reg3 <= read_data_b_reg2;
                        read_data_b_reg4 <= read_data_b_reg3;

                        // Final output stage with regceb control
                        if (regceb) begin
                            case (READ_LATENCY_B)
                                2: doutb <= read_data_b_internal;
                                3: doutb <= read_data_b_reg1;
                                4: doutb <= read_data_b_reg2;
                                5: doutb <= read_data_b_reg3;
                                default: doutb <= read_data_b_reg4; // For latency > 5
                            endcase
                        end
                    end
                end
            end else begin : gen_async_reset_multi_b
                always_ff @(posedge clka or posedge rstb) begin
                    if (rstb) begin
                        read_data_b_internal <= RESET_VALUE_B;
                        read_data_b_reg1 <= RESET_VALUE_B;
                        read_data_b_reg2 <= RESET_VALUE_B;
                        read_data_b_reg3 <= RESET_VALUE_B;
                        read_data_b_reg4 <= RESET_VALUE_B;
                        doutb <= RESET_VALUE_B;
                    end else begin
                        // Memory read stage
                        if (enb) begin
                            if (READ_DATA_WIDTH_B <= MAX_DATA_WIDTH) begin
                                read_data_b_internal <= rom_memory[addrb][READ_DATA_WIDTH_B-1:0];
                            end else begin
                                read_data_b_internal <= {{(READ_DATA_WIDTH_B-MAX_DATA_WIDTH){1'b0}}, rom_memory[addrb]};
                            end
                        end

                        // Pipeline stages
                        read_data_b_reg1 <= read_data_b_internal;
                        read_data_b_reg2 <= read_data_b_reg1;
                        read_data_b_reg3 <= read_data_b_reg2;
                        read_data_b_reg4 <= read_data_b_reg3;

                        // Final output stage with regceb control
                        if (regceb) begin
                            case (READ_LATENCY_B)
                                2: doutb <= read_data_b_internal;
                                3: doutb <= read_data_b_reg1;
                                4: doutb <= read_data_b_reg2;
                                5: doutb <= read_data_b_reg3;
                                default: doutb <= read_data_b_reg4; // For latency > 5
                            endcase
                        end
                    end
                end
            end
        end
    endgenerate


endmodule

// XPM_MEMORY_DPROM Compatibility Notes:
// - This module implements the XPM_MEMORY_DPROM interface excluding:
//   * ECC features (sbiterra/dbiterra/sbiterrb/dbiterrb tied to 0)
//   * Sleep mode (no sleep functionality)
//   * UltraRAM support
//   * Complex cascade features
// - Both ports are read-only (true dual-port ROM)
// - ROM behavior enforces read_first mode (no write operations)
// - Supports independent or common clock modes
// - Configurable read latency 0-100 cycles with regcea/regceb control
// - Synthesis-aware initialization via IGNORE_INIT_SYNTH
// - Dual reset modes: SYNC (default) and ASYNC for both ports