// Single Port RAM (SPRAM) - XPM_MEMORY_SPRAM Compatible
// Professional SystemVerilog implementation matching XPM interface
// Supports byte-wide writes, configurable read latency, and dual reset modes
// Excludes: ECC, sleep mode, UltraRAM, CASCADE features

module spram #(
    // XPM-compatible parameters with XPM default values
    parameter ADDR_WIDTH_A = 6,                    // Address width (1-20)
    parameter BYTE_WRITE_WIDTH_A = 8,             // Byte write width (1-4608)
    parameter IGNORE_INIT_SYNTH = 0,               // Ignore init in synthesis (0/1)
    parameter MEMORY_INIT_FILE = "none",           // Memory init file ("none" or filename)
    parameter MEMORY_SIZE = 2048,                  // Total memory size in bits
    parameter READ_DATA_WIDTH_A = 8,              // Read data width (1-4608)
    parameter READ_LATENCY_A = 2,                  // Read latency (0-100)
    parameter READ_RESET_VALUE_A = "0",            // Reset value for read data
    parameter RST_MODE_A = "SYNC",                 // Reset mode ("SYNC"/"ASYNC")
    parameter WRITE_DATA_WIDTH_A = 8,             // Write data width (1-4608)
    parameter WRITE_MODE_A = "read_first"          // Write mode
) (
    // Clock and reset
    input  logic                                    clka,       // Clock
    input  logic                                    rsta,       // Reset (sync/async based on RST_MODE_A)

    // Memory interface
    input  logic                                    ena,        // Enable
    input  logic [ADDR_WIDTH_A-1:0]               addra,      // Address
    input  logic [WRITE_DATA_WIDTH_A-1:0]         dina,       // Write data
    input  logic [WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-1:0] wea, // Write enable (vector)

    // Read interface
    output logic [READ_DATA_WIDTH_A-1:0]          douta,      // Read data
    input  logic                                    regcea,     // Register clock enable

    // ECC interface (tied off - no ECC support)
    output logic                                    sbiterra,   // Single bit error (always 0)
    output logic                                    dbiterra    // Double bit error (always 0)
);

    // Parameter validation
    initial begin
        if (READ_DATA_WIDTH_A != WRITE_DATA_WIDTH_A) begin
            $error("SPRAM: READ_DATA_WIDTH_A (%0d) must equal WRITE_DATA_WIDTH_A (%0d)",
                   READ_DATA_WIDTH_A, WRITE_DATA_WIDTH_A);
        end
        if (WRITE_DATA_WIDTH_A % BYTE_WRITE_WIDTH_A != 0) begin
            $error("SPRAM: WRITE_DATA_WIDTH_A (%0d) must be multiple of BYTE_WRITE_WIDTH_A (%0d)",
                   WRITE_DATA_WIDTH_A, BYTE_WRITE_WIDTH_A);
        end
        if (MEMORY_SIZE < WRITE_DATA_WIDTH_A) begin
            $error("SPRAM: MEMORY_SIZE (%0d) must be >= WRITE_DATA_WIDTH_A (%0d)",
                   MEMORY_SIZE, WRITE_DATA_WIDTH_A);
        end
    end

    // Local parameters
    localparam MEMORY_DEPTH = MEMORY_SIZE / WRITE_DATA_WIDTH_A;
    localparam WEA_WIDTH = WRITE_DATA_WIDTH_A / BYTE_WRITE_WIDTH_A;
    localparam RESET_VALUE = (READ_RESET_VALUE_A == "0") ? {READ_DATA_WIDTH_A{1'b0}} :
                            {READ_DATA_WIDTH_A{1'b1}}; // Simple parsing, could be enhanced

    // Memory array
    logic [WRITE_DATA_WIDTH_A-1:0] memory [0:MEMORY_DEPTH-1];

    // Internal read data signals
    logic [READ_DATA_WIDTH_A-1:0] read_data_internal;
    logic [READ_DATA_WIDTH_A-1:0] read_data_next; // Combinational next value
    logic [READ_DATA_WIDTH_A-1:0] read_data_reg1, read_data_reg2, read_data_reg3, read_data_reg4;

    // Combinational logic for read data next value - generated based on write mode
    generate
        if (WRITE_MODE_A == "read_first") begin : gen_read_first_logic
            always_comb begin
                if (ena) begin
                    // Return old data - same for both write and read operations
                    read_data_next = memory[addra];
                end else begin
                    read_data_next = read_data_internal; // Keep previous value when disabled
                end
            end
        end else if (WRITE_MODE_A == "write_first") begin : gen_write_first_logic
            always_comb begin
                if (ena) begin
                    // Return new data when writing, old data when reading
                    if (|wea) begin
                        // Construct the new data word with byte enables
                        logic [WRITE_DATA_WIDTH_A-1:0] new_data;
                        new_data = memory[addra]; // Start with old data
                        for (int i = 0; i < WEA_WIDTH; i++) begin
                            if (wea[i]) begin
                                new_data[(i+1)*BYTE_WRITE_WIDTH_A-1 -: BYTE_WRITE_WIDTH_A] =
                                    dina[(i+1)*BYTE_WRITE_WIDTH_A-1 -: BYTE_WRITE_WIDTH_A];
                            end
                        end
                        read_data_next = new_data;
                    end else begin
                        read_data_next = memory[addra]; // Normal read
                    end
                end else begin
                    read_data_next = read_data_internal; // Keep previous value when disabled
                end
            end
        end else if (WRITE_MODE_A == "no_change") begin : gen_no_change_logic
            always_comb begin
                if (ena) begin
                    // Don't change output when writing
                    if (!(|wea)) begin
                        read_data_next = memory[addra]; // Only update on read
                    end else begin
                        read_data_next = read_data_internal; // Keep previous value when writing
                    end
                end else begin
                    read_data_next = read_data_internal; // Keep previous value when disabled
                end
            end
        end else begin : gen_default_logic
            always_comb begin
                if (ena) begin
                    read_data_next = memory[addra];
                end else begin
                    read_data_next = read_data_internal; // Keep previous value when disabled
                end
            end
        end
    endgenerate

    // ECC outputs - always tied off (no ECC support)
    assign sbiterra = 1'b0;
    assign dbiterra = 1'b0;

    // Memory initialization based on IGNORE_INIT_SYNTH
    generate
        if (IGNORE_INIT_SYNTH == 0) begin : gen_init_both
            // Apply to both simulation and synthesis
            initial begin
                // ALWAYS initialize to zeros first (default safe state)
                for (int i = 0; i < MEMORY_DEPTH; i++) begin
                    memory[i] = {WRITE_DATA_WIDTH_A{1'b0}};
                end

                // THEN conditionally load from file (overlay)
                if (MEMORY_INIT_FILE != "none" && MEMORY_INIT_FILE != "") begin
                    $readmemh(MEMORY_INIT_FILE, memory);
                    $display("SPRAM: Loaded memory from file: %s", MEMORY_INIT_FILE);
                end else begin
                    $display("SPRAM: Initialized to zeros (no file specified)");
                end
            end
        end else begin : gen_init_sim_only
            // Simulation only initialization
            `ifdef SIMULATION
                initial begin
                    // ALWAYS initialize to zeros first (default safe state)
                    for (int i = 0; i < MEMORY_DEPTH; i++) begin
                        memory[i] = {WRITE_DATA_WIDTH_A{1'b0}};
                    end

                    // THEN conditionally load from file (overlay)
                    if (MEMORY_INIT_FILE != "none" && MEMORY_INIT_FILE != "") begin
                        $readmemh(MEMORY_INIT_FILE, memory);
                        $display("SPRAM: Loaded memory from file (simulation only): %s", MEMORY_INIT_FILE);
                    end else begin
                        $display("SPRAM: Initialized to zeros (simulation only)");
                    end
                end
            `else
                // In synthesis, always zero-initialize for safety
                initial begin
                    for (int i = 0; i < MEMORY_DEPTH; i++) begin
                        memory[i] = {WRITE_DATA_WIDTH_A{1'b0}};
                    end
                end
            `endif
        end
    endgenerate

    // Memory write operation with byte-wide write enable support
    // Memory contents are never affected by reset (both SYNC and ASYNC preserve memory)
    always_ff @(posedge clka) begin
        if (ena) begin
            for (int i = 0; i < WEA_WIDTH; i++) begin
                if (wea[i]) begin
                    memory[addra][(i+1)*BYTE_WRITE_WIDTH_A-1 -: BYTE_WRITE_WIDTH_A] <=
                        dina[(i+1)*BYTE_WRITE_WIDTH_A-1 -: BYTE_WRITE_WIDTH_A];
                end
            end
        end
    end

    // Memory read operation - simplified to use combinational read_data_next
    generate
        if (RST_MODE_A == "ASYNC") begin : gen_async_read
            always_ff @(posedge clka, posedge rsta) begin
                if (rsta) begin
                    read_data_internal <= RESET_VALUE;
                end else begin
                    read_data_internal <= read_data_next;
                end
            end
        end else begin : gen_sync_read
            always_ff @(posedge clka) begin
                if (rsta) begin
                    read_data_internal <= RESET_VALUE;
                end else begin
                    read_data_internal <= read_data_next;
                end
            end
        end
    endgenerate

    // Read latency pipeline implementation with regcea control
    generate
        if (READ_LATENCY_A == 0) begin : gen_combinational
            // Combinational read (latency 0) - not recommended for FPGA
            assign douta = ena ? memory[addra] : {READ_DATA_WIDTH_A{1'b0}};

        end else if (READ_LATENCY_A == 1) begin : gen_single_reg
            // Single cycle latency (registered output)
            assign douta = read_data_internal;

        end else if (READ_LATENCY_A == 2) begin : gen_double_reg
            // Two cycle latency with regcea control on final stage only
            if (RST_MODE_A == "ASYNC") begin : gen_async_lat2
                always_ff @(posedge clka, posedge rsta) begin
                    if (rsta) begin
                        read_data_reg1 <= RESET_VALUE;
                    end else if (regcea) begin
                        read_data_reg1 <= read_data_internal;
                    end
                end
            end else begin : gen_sync_lat2
                always_ff @(posedge clka) begin
                    if (rsta) begin
                        read_data_reg1 <= RESET_VALUE;
                    end else if (regcea) begin
                        read_data_reg1 <= read_data_internal;
                    end
                end
            end
            assign douta = read_data_reg1;

        end else if (READ_LATENCY_A == 3) begin : gen_triple_reg
            // Three cycle latency with regcea control on final stage only
            if (RST_MODE_A == "ASYNC") begin : gen_async_lat3
                always_ff @(posedge clka, posedge rsta) begin
                    if (rsta) begin
                        read_data_reg1 <= RESET_VALUE;
                        read_data_reg2 <= RESET_VALUE;
                    end else begin
                        read_data_reg1 <= read_data_internal;  // Always advances
                        if (regcea) begin
                            read_data_reg2 <= read_data_reg1;  // Final stage controlled by regcea
                        end
                    end
                end
            end else begin : gen_sync_lat3
                always_ff @(posedge clka) begin
                    if (rsta) begin
                        read_data_reg1 <= RESET_VALUE;
                        read_data_reg2 <= RESET_VALUE;
                    end else begin
                        read_data_reg1 <= read_data_internal;  // Always advances
                        if (regcea) begin
                            read_data_reg2 <= read_data_reg1;  // Final stage controlled by regcea
                        end
                    end
                end
            end
            assign douta = read_data_reg2;

        end else if (READ_LATENCY_A == 4) begin : gen_quad_reg
            // Four cycle latency with regcea control on final stage only
            if (RST_MODE_A == "ASYNC") begin : gen_async_lat4
                always_ff @(posedge clka, posedge rsta) begin
                    if (rsta) begin
                        read_data_reg1 <= RESET_VALUE;
                        read_data_reg2 <= RESET_VALUE;
                        read_data_reg3 <= RESET_VALUE;
                    end else begin
                        read_data_reg1 <= read_data_internal;  // Always advances
                        read_data_reg2 <= read_data_reg1;      // Always advances
                        if (regcea) begin
                            read_data_reg3 <= read_data_reg2;  // Final stage controlled by regcea
                        end
                    end
                end
            end else begin : gen_sync_lat4
                always_ff @(posedge clka) begin
                    if (rsta) begin
                        read_data_reg1 <= RESET_VALUE;
                        read_data_reg2 <= RESET_VALUE;
                        read_data_reg3 <= RESET_VALUE;
                    end else begin
                        read_data_reg1 <= read_data_internal;  // Always advances
                        read_data_reg2 <= read_data_reg1;      // Always advances
                        if (regcea) begin
                            read_data_reg3 <= read_data_reg2;  // Final stage controlled by regcea
                        end
                    end
                end
            end
            assign douta = read_data_reg3;

        end else begin : gen_max_reg
            // Maximum latency (5+ cycles) - simplified to 5 stages
            if (RST_MODE_A == "ASYNC") begin : gen_async_lat5
                always_ff @(posedge clka, posedge rsta) begin
                    if (rsta) begin
                        read_data_reg1 <= RESET_VALUE;
                        read_data_reg2 <= RESET_VALUE;
                        read_data_reg3 <= RESET_VALUE;
                        read_data_reg4 <= RESET_VALUE;
                    end else begin
                        read_data_reg1 <= read_data_internal;  // Always advances
                        read_data_reg2 <= read_data_reg1;      // Always advances
                        read_data_reg3 <= read_data_reg2;      // Always advances
                        if (regcea) begin
                            read_data_reg4 <= read_data_reg3;  // Final stage controlled by regcea
                        end
                    end
                end
            end else begin : gen_sync_lat5
                always_ff @(posedge clka) begin
                    if (rsta) begin
                        read_data_reg1 <= RESET_VALUE;
                        read_data_reg2 <= RESET_VALUE;
                        read_data_reg3 <= RESET_VALUE;
                        read_data_reg4 <= RESET_VALUE;
                    end else begin
                        read_data_reg1 <= read_data_internal;  // Always advances
                        read_data_reg2 <= read_data_reg1;      // Always advances
                        read_data_reg3 <= read_data_reg2;      // Always advances
                        if (regcea) begin
                            read_data_reg4 <= read_data_reg3;  // Final stage controlled by regcea
                        end
                    end
                end
            end
            assign douta = read_data_reg4;
        end
    endgenerate

    // Simulation assertions for debugging
    `ifdef SIMULATION
    always @(posedge clka) begin
        if (ena && addra >= MEMORY_DEPTH) begin
            $error("SPRAM: Address 0x%0h exceeds memory depth %0d", addra, MEMORY_DEPTH);
        end
        if (ena && |wea && addra >= MEMORY_DEPTH) begin
            $error("SPRAM: Write to address 0x%0h exceeds memory depth %0d", addra, MEMORY_DEPTH);
        end
    end

    // Display configuration at start of simulation
    initial begin
        $display("=== SPRAM Configuration ===");
        $display("ADDR_WIDTH_A: %0d", ADDR_WIDTH_A);
        $display("WRITE_DATA_WIDTH_A: %0d", WRITE_DATA_WIDTH_A);
        $display("READ_DATA_WIDTH_A: %0d", READ_DATA_WIDTH_A);
        $display("BYTE_WRITE_WIDTH_A: %0d", BYTE_WRITE_WIDTH_A);
        $display("MEMORY_SIZE: %0d bits", MEMORY_SIZE);
        $display("MEMORY_DEPTH: %0d words", MEMORY_DEPTH);
        $display("WEA_WIDTH: %0d bits", WEA_WIDTH);
        $display("READ_LATENCY_A: %0d", READ_LATENCY_A);
        $display("WRITE_MODE_A: %s", WRITE_MODE_A);
        $display("RST_MODE_A: %s", RST_MODE_A);
        $display("MEMORY_INIT_FILE: %s", MEMORY_INIT_FILE);
        $display("IGNORE_INIT_SYNTH: %0d", IGNORE_INIT_SYNTH);
        $display("========================");
    end
    `endif

endmodule
