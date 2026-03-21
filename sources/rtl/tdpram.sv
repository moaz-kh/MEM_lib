// True Dual Port RAM (TDPRAM) - Common clock implementation
// Both ports support independent read/write. Port A wins on same-address write collision.
// Supports read_first, write_first, no_change write modes per port.
// Single always_ff block avoids multi-driver issues on shared memory array.

module tdpram #(
    parameter DATA_WIDTH_A = 32,
    parameter DATA_WIDTH_B = 32,
    parameter ADDR_WIDTH_A = 10,
    parameter ADDR_WIDTH_B = 10,
    parameter MEMORY_SIZE = DATA_WIDTH_A * (2**ADDR_WIDTH_A),
    parameter READ_LATENCY_A = 1,
    parameter READ_LATENCY_B = 1,
    parameter WRITE_MODE_A = "read_first",
    parameter WRITE_MODE_B = "read_first",
    parameter MEMORY_PRIMITIVE = "auto",
    parameter MEMORY_INIT_FILE = "",
    parameter USE_MEM_INIT = 0,
    parameter AUTO_SLEEP_TIME = 0,
    parameter MESSAGE_CONTROL = 0,
    parameter READ_RESET_VALUE_A = "0",
    parameter READ_RESET_VALUE_B = "0",
    parameter ECC_MODE = "no_ecc",
    parameter MEMORY_OPTIMIZATION = "true",
    parameter WAKEUP_TIME = "disable_sleep"
) (
    // Port A interface (read/write)
    input  logic                      clka,
    input  logic                      rsta,
    input  logic                      ena,
    input  logic                      wea,
    input  logic [ADDR_WIDTH_A-1:0]  addra,
    input  logic [DATA_WIDTH_A-1:0]  dina,
    output logic [DATA_WIDTH_A-1:0]  douta,

    // Port B interface (read/write)
    // clkb removed — common clock: Port B shares clka
    input  logic                      rstb,
    input  logic                      enb,
    input  logic                      web,
    input  logic [ADDR_WIDTH_B-1:0]  addrb,
    input  logic [DATA_WIDTH_B-1:0]  dinb,
    output logic [DATA_WIDTH_B-1:0]  doutb,

    // Power management and error injection (compatibility ports, unused)
    input  logic                      sleep,
    input  logic                      injectsbiterra,
    input  logic                      injectdbiterra,
    input  logic                      injectsbiterrb,
    input  logic                      injectdbiterrb
);

    localparam MEMORY_DEPTH = 2**ADDR_WIDTH_A;

    logic [DATA_WIDTH_A-1:0] memory [0:MEMORY_DEPTH-1];
    logic [DATA_WIDTH_A-1:0] read_data_a_internal;
    logic [DATA_WIDTH_B-1:0] read_data_b_internal;

    // Memory initialisation
    initial begin
        if (USE_MEM_INIT && MEMORY_INIT_FILE != "")
            $readmemh(MEMORY_INIT_FILE, memory);
        else
            for (int i = 0; i < MEMORY_DEPTH; i++) memory[i] = '0;
    end

    // Single always block — avoids multi-driver issues on shared memory array.
    // Port B writes first (blocking =) so Port A wins on same-address collision.
    always_ff @(posedge clka) begin
        // ---- resets ----
        if (rsta) read_data_a_internal <= '0;
        if (rstb) read_data_b_internal <= '0;

        // ---- Port B (lower priority) ----
        if (!rstb && enb) begin
            case (WRITE_MODE_B)
                "read_first": begin
                    read_data_b_internal <= memory[addrb];
                    if (web) memory[addrb] = dinb;
                end
                "write_first": begin
                    if (web) memory[addrb] = dinb;
                    read_data_b_internal <= memory[addrb];
                end
                "no_change": begin
                    if (web) memory[addrb] = dinb;
                    else     read_data_b_internal <= memory[addrb];
                end
                default: begin
                    read_data_b_internal <= memory[addrb];
                    if (web) memory[addrb] = dinb;
                end
            endcase
        end

        // ---- Port A (higher priority — overwrites B on collision) ----
        if (!rsta && ena) begin
            case (WRITE_MODE_A)
                "read_first": begin
                    read_data_a_internal <= memory[addra];
                    if (wea) memory[addra] = dina;
                end
                "write_first": begin
                    if (wea) memory[addra] = dina;
                    read_data_a_internal <= memory[addra];
                end
                "no_change": begin
                    if (wea) memory[addra] = dina;
                    else     read_data_a_internal <= memory[addra];
                end
                default: begin
                    read_data_a_internal <= memory[addra];
                    if (wea) memory[addra] = dina;
                end
            endcase
        end
    end

    assign douta = read_data_a_internal;
    assign doutb = read_data_b_internal;

endmodule
