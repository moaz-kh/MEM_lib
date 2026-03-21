// Dual Port Distributed RAM (DPDISTRAM) - XPM_MEMORY_DPDISTRAM Compatible
// Professional SystemVerilog implementation matching XPM interface
// Port A: Read/Write with byte-enable support
// Port B: Read-only access
// Distributed RAM implementation with configurable read latency

module dpdistram #(
    // Essential parameters only
    parameter ADDR_WIDTH_A = 4,                    // Address width for Port A (1-20)
    parameter ADDR_WIDTH_B = 4,                    // Address width for Port B (1-20)
    parameter BYTE_WRITE_WIDTH_A = 8,              // Byte write width for Port A
    parameter IGNORE_INIT_SYNTH = 0,               // Ignore init in synthesis (0/1)
    parameter MEMORY_INIT_FILE = "none",           // Memory init file ("none" or filename)
    parameter MEMORY_SIZE = 512,                   // Total memory size in bits
    parameter READ_DATA_WIDTH_A = 8,               // Read data width for Port A (1-4608)
    parameter READ_DATA_WIDTH_B = 8,               // Read data width for Port B (1-4608)
    parameter READ_LATENCY_A = 1,                  // Read latency for Port A (0-100)
    parameter READ_LATENCY_B = 1,                  // Read latency for Port B (0-100)
    parameter READ_RESET_VALUE_A = "0",            // Reset value for Port A read data
    parameter READ_RESET_VALUE_B = "0",            // Reset value for Port B read data
    parameter RST_MODE_A = "SYNC",                 // Reset mode for Port A ("SYNC"/"ASYNC")
    parameter RST_MODE_B = "SYNC",                 // Reset mode for Port B ("SYNC"/"ASYNC")
    parameter USE_MEM_INIT = 1,                    // Use memory initialization
    parameter WRITE_DATA_WIDTH_A = 8               // Write data width for Port A (1-4608)
) (
    // Port A interface (Read/Write)
    input  logic                                clka,       // Port A clock
    input  logic                                rsta,       // Port A reset
    input  logic                                ena,        // Port A memory enable
    input  logic                                regcea,     // Port A register clock enable
    input  logic [WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-1:0] wea, // Port A byte-wide write enable
    input  logic [ADDR_WIDTH_A-1:0]           addra,      // Port A address
    input  logic [WRITE_DATA_WIDTH_A-1:0]     dina,       // Port A write data
    output logic [READ_DATA_WIDTH_A-1:0]      douta,      // Port A read data

    // Port B interface (Read-only)
    // clkb removed — common clock: Port B shares clka
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
    output logic                                dbiterrb    // Double bit error Port B (always 0)
);

    // Local parameters
    localparam MEMORY_DEPTH_A = MEMORY_SIZE / READ_DATA_WIDTH_A;
    localparam MEMORY_DEPTH_B = MEMORY_SIZE / READ_DATA_WIDTH_B;
    localparam RESET_VALUE_A = (READ_RESET_VALUE_A == "0") ? {READ_DATA_WIDTH_A{1'b0}} :
                              {READ_DATA_WIDTH_A{1'b1}}; // Simple parsing
    localparam RESET_VALUE_B = (READ_RESET_VALUE_B == "0") ? {READ_DATA_WIDTH_B{1'b0}} :
                              {READ_DATA_WIDTH_B{1'b1}}; // Simple parsing
    localparam NUM_BYTES_A = WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A;

    // Memory array - distributed RAM implementation
    logic [READ_DATA_WIDTH_A-1:0] dist_memory [0:MEMORY_DEPTH_A-1];

    // Internal read data signals for Port A
    logic [READ_DATA_WIDTH_A-1:0] read_data_a_reg1, read_data_a_reg2, read_data_a_reg3, read_data_a_reg4;
    logic [READ_DATA_WIDTH_A-1:0] read_data_a_internal;
    // Internal read data signals for Port B
    logic [READ_DATA_WIDTH_B-1:0] read_data_b_internal; // For combinational latency only
    logic [READ_DATA_WIDTH_B-1:0] read_data_b_reg1, read_data_b_reg2, read_data_b_reg3, read_data_b_reg4;

    // ECC outputs (always 0 - no ECC support)
    assign sbiterra = 1'b0;
    assign dbiterra = 1'b0;
    assign sbiterrb = 1'b0;
    assign dbiterrb = 1'b0;

    // Memory initialization with synthesis control
    generate
        if (IGNORE_INIT_SYNTH == 0) begin : gen_init_both
            initial begin
                for (int i = 0; i < MEMORY_DEPTH_A; i++)
                    dist_memory[i] = {READ_DATA_WIDTH_A{1'b0}};
                if (MEMORY_INIT_FILE != "none" && MEMORY_INIT_FILE != "")
                    $readmemh(MEMORY_INIT_FILE, dist_memory);
            end
        end else begin : gen_init_sim_only
            `ifdef SIMULATION
            initial begin
                for (int i = 0; i < MEMORY_DEPTH_A; i++)
                    dist_memory[i] = {READ_DATA_WIDTH_A{1'b0}};
                if (MEMORY_INIT_FILE != "none" && MEMORY_INIT_FILE != "")
                    $readmemh(MEMORY_INIT_FILE, dist_memory);
            end
            `endif
        end
    endgenerate

    // Write with byte enable
    always_ff @(posedge clka) begin
        if (ena) begin
            for (int byte_idx = 0; byte_idx < NUM_BYTES_A; byte_idx++) begin
                if (wea[byte_idx]) begin
                    dist_memory[addra][byte_idx*8 +: 8] <= dina[byte_idx*8 +: 8];
                end
            end
        end
    end
            
    // Single cycle latency - read-first behavior for distributed RAM
    generate
        if (RST_MODE_A == "SYNC") begin : gen_sync_reset_read_data_a
            always_ff @(posedge clka) begin
                if (rsta) begin
                    read_data_a_internal <= RESET_VALUE_A;
                end else if (ena) begin
                    read_data_a_internal = dist_memory[addra];
                end
            end 
        end else begin : gen_async_reset_read_data_a
            always_ff @(posedge clka or posedge rsta) begin
                if (rsta) begin
                    read_data_a_internal <= RESET_VALUE_A;
                end else if (ena) begin
                    read_data_a_internal = dist_memory[addra];
                end
            end 
        end
    endgenerate      
    
    // Port A: Read/Write operations with byte-enable support
    generate
        if (READ_LATENCY_A == 0) begin : gen_comb_a
            // Combinational read/write (latency 0)
            assign douta = (ena)? dist_memory[addra] : RESET_VALUE_A;

        end else if (READ_LATENCY_A == 1) begin : gen_latency_1_a
            assign douta = read_data_a_internal;
        
        end else if (READ_LATENCY_A == 2) begin : gen_latency_2_a    
            // 2-cycle latency - proper shift register pipeline
            if (RST_MODE_A == "SYNC") begin : gen_sync_reset_multi_a
                always_ff @(posedge clka) begin
                    if (rsta) begin
                        read_data_a_reg1 <= RESET_VALUE_A;
                    end else begin
                        // Shift register pipeline - advance all stages when enabled
                        if (regcea) read_data_a_reg1 <= read_data_a_internal; 
                    end
                end

            end else begin : gen_async_reset_multi_a
                always_ff @(posedge clka or posedge rsta) begin
                    if (rsta) begin
                        read_data_a_reg1 <= RESET_VALUE_A;
                    end else begin
                        // Shift register pipeline - advance all stages when enabled
                        if (regcea) read_data_a_reg1 <= read_data_a_internal;  
                    end
                end
            end
            assign douta = read_data_a_reg1;
        
        end else if (READ_LATENCY_A == 3) begin : gen_latency_3_a    
            // 2-cycle latency - proper shift register pipeline
            if (RST_MODE_A == "SYNC") begin : gen_sync_reset_multi_a
                always_ff @(posedge clka) begin
                    if (rsta) begin
                        read_data_a_reg1 <= RESET_VALUE_A;
                        read_data_a_reg2 <= RESET_VALUE_A;
                    end else begin
                        // Shift register pipeline - advance all stages when enabled
                        read_data_a_reg1 <= read_data_a_internal;  
                        if (regcea) read_data_a_reg2 <= read_data_a_reg1;  
                    end
                end
            end else begin : gen_async_reset_multi_a
                always_ff @(posedge clka or posedge rsta) begin
                    if (rsta) begin
                        read_data_a_reg1 <= RESET_VALUE_A;
                        read_data_a_reg2 <= RESET_VALUE_A;
                    end else begin
                        // Shift register pipeline - advance all stages when enabled
                        read_data_a_reg1 <= read_data_a_internal;  
                        if (regcea) read_data_a_reg2 <= read_data_a_reg1;  
                    end
                end
            end
            assign douta = read_data_a_reg2;
        
        end else if (READ_LATENCY_A == 4) begin : gen_latency_4_a    
            // 2-cycle latency - proper shift register pipeline
            if (RST_MODE_A == "SYNC") begin : gen_sync_reset_multi_a
                always_ff @(posedge clka) begin
                    if (rsta) begin
                        read_data_a_reg1 <= RESET_VALUE_A;
                        read_data_a_reg2 <= RESET_VALUE_A;
                        read_data_a_reg3 <= RESET_VALUE_A;
                    end else begin
                        // Shift register pipeline - advance all stages when enabled
                        read_data_a_reg1 <= read_data_a_internal;  
                        read_data_a_reg2 <= read_data_a_reg1;  
                        if (regcea) read_data_a_reg3 <= read_data_a_reg2;  
                    end
                end
            end else begin : gen_async_reset_multi_a
                always_ff @(posedge clka or posedge rsta) begin
                    if (rsta) begin
                        read_data_a_reg1 <= RESET_VALUE_A;
                        read_data_a_reg2 <= RESET_VALUE_A;
                        read_data_a_reg3 <= RESET_VALUE_A;
                    end else begin
                        // Shift register pipeline - advance all stages when enabled
                        read_data_a_reg1 <= read_data_a_internal;  
                        read_data_a_reg2 <= read_data_a_reg1;  
                        if (regcea) read_data_a_reg3 <= read_data_a_reg2;  
                    end
                end
            end
            assign douta = read_data_a_reg3;
        
        end else begin : gen_latency_multi_a
            // Multi-cycle latency (5+ cycles) - proper shift register pipeline
            if (RST_MODE_A == "SYNC") begin : gen_sync_reset_multi_a
                always_ff @(posedge clka) begin
                    if (rsta) begin
                        read_data_a_reg1 <= RESET_VALUE_A;
                        read_data_a_reg2 <= RESET_VALUE_A;
                        read_data_a_reg3 <= RESET_VALUE_A;
                        read_data_a_reg4 <= RESET_VALUE_A;
                    end else begin 
                        read_data_a_reg1 <= read_data_a_internal;
                        read_data_a_reg2 <= read_data_a_reg1;
                        read_data_a_reg3 <= read_data_a_reg2;
                        if (regcea) read_data_a_reg4 <= read_data_a_reg3; 
                    end
                end 
            end else begin : gen_async_reset_multi_a
                always_ff @(posedge clka or posedge rsta) begin
                    if (rsta) begin
                        read_data_a_reg1 <= RESET_VALUE_A;
                        read_data_a_reg2 <= RESET_VALUE_A;
                        read_data_a_reg3 <= RESET_VALUE_A;
                        read_data_a_reg4 <= RESET_VALUE_A;
                    end else begin 
                        read_data_a_reg1 <= read_data_a_internal;
                        read_data_a_reg2 <= read_data_a_reg1;
                        read_data_a_reg3 <= read_data_a_reg2;
                        if (regcea) read_data_a_reg4 <= read_data_a_reg3; 
                    end
                end
            end
            assign douta = read_data_a_reg4;  
        end
    endgenerate

  
    // Port B base read register (1-cycle) - clocked by clka (common clock), gated by enb
    generate
        if (RST_MODE_B == "SYNC") begin : gen_sync_reset_read_data_b
            always_ff @(posedge clka) begin
                if (rstb) begin
                    read_data_b_internal <= RESET_VALUE_B;
                end else if (enb) begin
                    read_data_b_internal = dist_memory[addrb];
                end
            end
        end else begin : gen_async_reset_read_data_b
            always_ff @(posedge clka or posedge rstb) begin
                if (rstb) begin
                    read_data_b_internal <= RESET_VALUE_B;
                end else if (enb) begin
                    read_data_b_internal = dist_memory[addrb];
                end
            end
        end
    endgenerate
    
    // Port B: Read-only operations
    generate
        if (READ_LATENCY_B == 0) begin : gen_comb_b
            // Combinational read (latency 0) 
            assign doutb = dist_memory[addrb];
        end else if (READ_LATENCY_B == 1) begin : gen_latency_1_b
            // Single cycle latency
            if (RST_MODE_B == "SYNC") begin : gen_sync_reset_1_b
                always_ff @(posedge clka) begin
                    if (rstb) begin
                        read_data_b_reg1 <= RESET_VALUE_B;
                    end else begin 
                        if (regceb)read_data_b_reg1 <= read_data_b_internal; 
                    end
                end
            end else begin : gen_async_reset_1_b
                always_ff @(posedge clka or posedge rstb) begin
                    if (rstb) begin
                        read_data_b_reg1 <= RESET_VALUE_B;
                    end else begin 
                        if (regceb)read_data_b_reg1 <= read_data_b_internal; 
                    end
                end
            end
            assign doutb = read_data_b_reg1;
            
        end else if (READ_LATENCY_B == 2) begin : gen_latency_2_b
            // double cycle latency
            if (RST_MODE_B == "SYNC") begin : gen_sync_reset_1_b
                always_ff @(posedge clka) begin
                    if (rstb) begin
                        read_data_b_reg1 <= RESET_VALUE_B;
                        read_data_b_reg2 <= RESET_VALUE_B;
                    end else begin 
                        read_data_b_reg1 <= read_data_b_internal; 
                        if (regceb)read_data_b_reg2 <= read_data_b_reg1; 
                    end
                end
            end else begin : gen_async_reset_1_b
                always_ff @(posedge clka or posedge rstb) begin
                    if (rstb) begin
                        read_data_b_reg1 <= RESET_VALUE_B;
                        read_data_b_reg2 <= RESET_VALUE_B;
                    end else begin 
                        read_data_b_reg1 <= read_data_b_internal; 
                        if (regceb)read_data_b_reg2 <= read_data_b_reg1; 
                    end
                end
            end
            assign doutb = read_data_b_reg2;
            
        end else if (READ_LATENCY_B == 3) begin : gen_latency_3_b
            // double cycle latency
            if (RST_MODE_B == "SYNC") begin : gen_sync_reset_1_b
                always_ff @(posedge clka) begin
                    if (rstb) begin
                        read_data_b_reg1 <= RESET_VALUE_B;
                        read_data_b_reg2 <= RESET_VALUE_B;
                        read_data_b_reg3 <= RESET_VALUE_B;
                    end else begin 
                        read_data_b_reg1 <= read_data_b_internal; 
                        read_data_b_reg2 <= read_data_b_reg1; 
                        if (regceb)read_data_b_reg3 <= read_data_b_reg2; 
                    end
                end
            end else begin : gen_async_reset_1_b
                always_ff @(posedge clka or posedge rstb) begin
                    if (rstb) begin
                        read_data_b_reg1 <= RESET_VALUE_B;
                        read_data_b_reg2 <= RESET_VALUE_B;
                        read_data_b_reg3 <= RESET_VALUE_B;
                    end else begin 
                        read_data_b_reg1 <= read_data_b_internal; 
                        read_data_b_reg2 <= read_data_b_reg1; 
                        if (regceb)read_data_b_reg3 <= read_data_b_reg2; 
                    end
                end
            end
            assign doutb = read_data_b_reg3;
            
        end else begin : gen_latency_multi_b
            // Multi-cycle latency (2+ cycles) - proper shift register pipeline
            if (RST_MODE_B == "SYNC") begin : gen_sync_reset_multi_b
                always_ff @(posedge clka) begin
                    if (rstb) begin
                        read_data_b_reg1 <= RESET_VALUE_B;
                        read_data_b_reg2 <= RESET_VALUE_B;
                        read_data_b_reg3 <= RESET_VALUE_B;
                        read_data_b_reg4 <= RESET_VALUE_B;
                    end else begin 
                        read_data_b_reg1 <= read_data_b_internal; 
                        read_data_b_reg2 <= read_data_b_reg1; 
                        read_data_b_reg3 <= read_data_b_reg2; 
                        if (regceb)read_data_b_reg4 <= read_data_b_reg3; 
                    end
                end
            end else begin : gen_async_reset_multi_b
                always_ff @(posedge clka or posedge rstb) begin
                    if (rstb) begin
                        read_data_b_reg1 <= RESET_VALUE_B;
                        read_data_b_reg2 <= RESET_VALUE_B;
                        read_data_b_reg3 <= RESET_VALUE_B;
                        read_data_b_reg4 <= RESET_VALUE_B;
                    end else begin 
                        read_data_b_reg1 <= read_data_b_internal; 
                        read_data_b_reg2 <= read_data_b_reg1; 
                        read_data_b_reg3 <= read_data_b_reg2; 
                        if (regceb)read_data_b_reg4 <= read_data_b_reg3; 
                    end
                end
            end
            assign doutb = read_data_b_reg4;
        end
    endgenerate

endmodule

// XPM_MEMORY_DPDISTRAM Compatibility Notes:
// - This module implements the XPM_MEMORY_DPDISTRAM interface excluding:
//   * ECC features (sbiterra/dbiterra/sbiterrb/dbiterrb tied to 0)
//   * Sleep mode (no sleep functionality)
//   * Complex memory optimization features
// - Port A supports read/write with byte-wide write enables
// - Port B is read-only
// - Supports independent or common clock modes
// - Distributed RAM implementation with configurable read latency
// - Synthesis-aware initialization via IGNORE_INIT_SYNTH
// - Dual reset modes: SYNC (default) and ASYNC for both ports
