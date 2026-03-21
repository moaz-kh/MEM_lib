// Dual Port RAM (DPRAM) - Common clock implementation
// Both ports share clka. Port A has write priority on address collision.
// Supports read_first, write_first, no_change write modes per port.

module dpram #(
    parameter DATA_WIDTH    = 8,             // Data width for both ports
    parameter ADDR_WIDTH    = 4,             // Address width for both ports
    parameter WRITE_MODE_A  = "read_first",  // Port A: "read_first","write_first","no_change"
    parameter WRITE_MODE_B  = "read_first",  // Port B: "read_first","write_first","no_change"
    parameter USE_MEM_INIT  = 0,             // 1 = load MEMORY_INIT_FILE at startup
    parameter MEMORY_INIT_FILE = "",         // Hex init file path
    parameter MESSAGE_CONTROL = 0           // 1 = print collision messages
) (
    input  logic                    clka,
    input  logic                    rsta,
    input  logic                    ena,
    input  logic                    wea,
    input  logic [ADDR_WIDTH-1:0]  addra,
    input  logic [DATA_WIDTH-1:0]  dina,
    output logic [DATA_WIDTH-1:0]  douta,

    input  logic                    rstb,
    input  logic                    enb,
    input  logic                    web,
    input  logic [ADDR_WIDTH-1:0]  addrb,
    input  logic [DATA_WIDTH-1:0]  dinb,
    output logic [DATA_WIDTH-1:0]  doutb
);

    localparam DEPTH = 2**ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [DATA_WIDTH-1:0] rdata_a, rdata_b;

    // Memory initialisation
    initial begin
        if (USE_MEM_INIT && MEMORY_INIT_FILE != "")
            $readmemh(MEMORY_INIT_FILE, mem);
        else
            for (int i = 0; i < DEPTH; i++) mem[i] = '0;
    end

    // Single always block - avoids Icarus multi-driver issues on shared memory array.
    // Port B writes first so Port A wins on same-address collision.
    always_ff @(posedge clka) begin
        // ---- resets ----
        if (rsta) rdata_a <= '0;
        if (rstb) rdata_b <= '0;

        // ---- Port B ----
        if (!rstb && enb) begin
            case (WRITE_MODE_B)
                "read_first": begin
                    rdata_b        <= mem[addrb];
                    if (web) mem[addrb] = dinb;
                end
                "write_first": begin
                    if (web) mem[addrb] = dinb;
                    rdata_b <= mem[addrb];
                end
                "no_change": begin
                    if (web) mem[addrb] = dinb;
                    else     rdata_b <= mem[addrb];
                end
                default: begin
                    rdata_b        <= mem[addrb];
                    if (web) mem[addrb] = dinb;
                end
            endcase
        end

        // ---- Port A (higher priority - overwrites B on collision) ----
        if (!rsta && ena) begin
            case (WRITE_MODE_A)
                "read_first": begin
                    rdata_a        <= mem[addra];
                    if (wea) mem[addra] = dina;
                end
                "write_first": begin
                    if (wea) mem[addra] = dina;
                    rdata_a <= mem[addra];
                end
                "no_change": begin
                    if (wea) mem[addra] = dina;
                    else     rdata_a <= mem[addra];
                end
                default: begin
                    rdata_a        <= mem[addra];
                    if (wea) mem[addra] = dina;
                end
            endcase
        end
    end

    assign douta = rdata_a;
    assign doutb = rdata_b;

endmodule
