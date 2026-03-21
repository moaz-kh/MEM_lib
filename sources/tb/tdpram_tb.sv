// True Dual Port RAM Testbench - Advanced collision testing
// Both ports support read/write operations with complex collision scenarios
// Self-checking with detailed pass/fail reporting

`timescale 1ns / 1ps

module tdpram_tb;

    // Test parameters
    localparam DATA_WIDTH_A = 32;
    localparam DATA_WIDTH_B = 32;
    localparam ADDR_WIDTH_A = 8;
    localparam ADDR_WIDTH_B = 8;
    localparam MEMORY_DEPTH = 2**ADDR_WIDTH_A;
    localparam CLK_PERIOD = 10;

    // DUT signals
    logic                      clka, clkb;
    logic                      rsta, rstb;
    logic                      ena, enb;
    logic                      wea, web;
    logic [ADDR_WIDTH_A-1:0]  addra;
    logic [ADDR_WIDTH_B-1:0]  addrb;
    logic [DATA_WIDTH_A-1:0]  dina;
    logic [DATA_WIDTH_B-1:0]  dinb;
    logic [DATA_WIDTH_A-1:0]  douta;
    logic [DATA_WIDTH_B-1:0]  doutb;
    logic                      sleep;
    logic                      injectsbiterra, injectdbiterra;
    logic                      injectsbiterrb, injectdbiterrb;

    // Test control
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    string current_test = "";

    // Clock generation - common clock (clkb = clka per single-clock rule)
    initial begin
        clka = 0;
        forever #(CLK_PERIOD/2) clka = ~clka;
    end
    assign clkb = clka;

    // DUT instantiation
    tdpram #(
        .DATA_WIDTH_A(DATA_WIDTH_A),
        .DATA_WIDTH_B(DATA_WIDTH_B),
        .ADDR_WIDTH_A(ADDR_WIDTH_A),
        .ADDR_WIDTH_B(ADDR_WIDTH_B),
        .READ_LATENCY_A(1),
        .READ_LATENCY_B(1),
        .WRITE_MODE_A("read_first"),
        .WRITE_MODE_B("read_first"),
        .MESSAGE_CONTROL(1)
    ) dut (
        .clka(clka),
        .rsta(rsta), .rstb(rstb),
        .ena(ena), .enb(enb),
        .wea(wea), .web(web),
        .addra(addra), .addrb(addrb),
        .dina(dina), .dinb(dinb),
        .douta(douta), .doutb(doutb),
        .sleep(sleep),
        .injectsbiterra(injectsbiterra),
        .injectdbiterra(injectdbiterra),
        .injectsbiterrb(injectsbiterrb),
        .injectdbiterrb(injectdbiterrb)
    );

    // Test procedures
    task automatic reset_system();
        rsta = 1; rstb = 1;
        ena = 0; enb = 0;
        wea = 0; web = 0;
        addra = 0; addrb = 0;
        dina = 0; dinb = 0;
        sleep = 0;
        injectsbiterra = 0; injectdbiterra = 0;
        injectsbiterrb = 0; injectdbiterrb = 0;
        repeat(3) @(posedge clka);
        rsta = 0; rstb = 0;
        repeat(2) @(posedge clka);
        $display("[INFO] System reset completed");
    endtask

    task automatic write_port_a(input [ADDR_WIDTH_A-1:0] addr, input [DATA_WIDTH_A-1:0] data);
        @(posedge clka);
        ena = 1; wea = 1;
        addra = addr; dina = data;
        @(posedge clka);
        wea = 0;
    endtask

    task automatic write_port_b(input [ADDR_WIDTH_B-1:0] addr, input [DATA_WIDTH_B-1:0] data);
        enb = 1; web = 1;
        addrb = addr; dinb = data;
        @(posedge clkb);
        web = 0;
    endtask

    task automatic read_port_a(input [ADDR_WIDTH_A-1:0] addr);
        @(posedge clka);
        ena = 1; wea = 0;
        addra = addr;
        @(posedge clka);
    endtask

    task automatic read_port_b(input [ADDR_WIDTH_B-1:0] addr);
        @(posedge clkb);
        enb = 1; web = 0;
        addrb = addr;
        @(posedge clkb); // address presented to RAM
        @(posedge clkb); // registered output now stable
    endtask

    task automatic check_result_a(input [DATA_WIDTH_A-1:0] expected, input string test_name);
        test_count++;
        if (douta === expected) begin
            pass_count++;
            $display("[PASS] %s (Port A): Expected=0x%08x, Got=0x%08x", test_name, expected, douta);
        end else begin
            fail_count++;
            $display("[FAIL] %s (Port A): Expected=0x%08x, Got=0x%08x", test_name, expected, douta);
        end
    endtask

    task automatic check_result_b(input [DATA_WIDTH_B-1:0] expected, input string test_name);
        test_count++;
        if (doutb === expected) begin
            pass_count++;
            $display("[PASS] %s (Port B): Expected=0x%08x, Got=0x%08x", test_name, expected, doutb);
        end else begin
            fail_count++;
            $display("[FAIL] %s (Port B): Expected=0x%08x, Got=0x%08x", test_name, expected, doutb);
        end
    endtask

    // Test basic read/write on both ports
    task automatic test_basic_operations();
        current_test = "Basic Read/Write Operations";
        $display("\n=== %s Test ===", current_test);

        // Test Port A write/read
        write_port_a(8'h10, 32'hAAAA1111);
        read_port_a(8'h10);
        check_result_a(32'hAAAA1111, "Port A basic write/read");

        // Test Port B write/read
        write_port_b(8'h20, 32'hBBBB2222);
        read_port_b(8'h20);
        check_result_b(32'hBBBB2222, "Port B basic write/read");

        // Cross-port reading
        read_port_a(8'h20);
        check_result_a(32'hBBBB2222, "Port A reads Port B data");

        read_port_b(8'h10);
        check_result_b(32'hAAAA1111, "Port B reads Port A data");
    endtask

    // Test write collision scenarios
    task automatic test_write_collisions();
        current_test = "Write Collision Testing";
        $display("\n=== %s Test ===", current_test);

        // Simultaneous writes to same address
        $display("[INFO] Testing simultaneous write collision (Port A should win)");
        @(posedge clka);
        ena = 1; enb = 1;
        wea = 1; web = 1;
        addra = 8'h30; addrb = 8'h30;
        dina = 32'h11111111; dinb = 32'h22222222;
        @(posedge clka);
        wea = 0; web = 0;

        // Check which write won
        read_port_a(8'h30);
        check_result_a(32'h11111111, "Write collision - Port A should win");

        read_port_b(8'h30);
        check_result_b(32'h11111111, "Write collision - Port B sees Port A data");
    endtask

    // Test both ports writing to different addresses simultaneously
    task automatic test_simultaneous_writes();
        current_test = "Simultaneous Non-Colliding Writes";
        $display("\n=== %s Test ===", current_test);

        // Both ports write simultaneously to different addresses
        @(posedge clka);
        ena = 1; enb = 1;
        wea = 1; web = 1;
        addra = 8'h40; addrb = 8'h41;
        dina = 32'h40404040; dinb = 32'h41414141;
        @(posedge clka);
        wea = 0; web = 0;

        // Verify both writes succeeded
        read_port_a(8'h40);
        check_result_a(32'h40404040, "Port A simultaneous write");

        read_port_b(8'h41);
        check_result_b(32'h41414141, "Port B simultaneous write");

        // Cross-verify
        read_port_a(8'h41);
        check_result_a(32'h41414141, "Port A reads Port B simultaneous write");

        read_port_b(8'h40);
        check_result_b(32'h40404040, "Port B reads Port A simultaneous write");
    endtask

    // Test read while other port writes
    task automatic test_read_during_write();
        current_test = "Read During Write Operations";
        $display("\n=== %s Test ===", current_test);

        // Pre-populate some data
        write_port_a(8'h50, 32'h50505050);

        // Port A writes while Port B reads same address
        @(posedge clka);
        ena = 1; enb = 1;
        wea = 1; web = 0;
        addra = 8'h50; addrb = 8'h50;
        dina = 32'h51515151;
        @(posedge clka);
        wea = 0;

        check_result_b(32'h50505050, "Port B reads old value during Port A write (read-first)");

        // Verify write completed
        read_port_a(8'h50);
        check_result_a(32'h51515151, "Port A write completed");
    endtask

    // Test boundary addresses
    task automatic test_boundary_addresses();
        current_test = "Boundary Address Testing";
        $display("\n=== %s Test ===", current_test);

        // Test minimum addresses
        write_port_a(8'h00, 32'h00000001);
        write_port_b(8'h01, 32'h01010101);

        read_port_a(8'h00);
        check_result_a(32'h00000001, "Port A minimum address");

        read_port_b(8'h01);
        check_result_b(32'h01010101, "Port B near minimum address");

        // Test maximum addresses
        write_port_a(8'hFE, 32'hFEFEFEFE);
        write_port_b(8'hFF, 32'hFFFFFFFF);

        read_port_a(8'hFE);
        check_result_a(32'hFEFEFEFE, "Port A near maximum address");

        read_port_b(8'hFF);
        check_result_b(32'hFFFFFFFF, "Port B maximum address");
    endtask

    // Test random operations
    task automatic test_random_operations();
        logic [DATA_WIDTH_A-1:0] random_data_a, random_data_b;
        logic [ADDR_WIDTH_A-1:0] random_addr_a, random_addr_b;

        current_test = "Random Operations";
        $display("\n=== %s Test ===", current_test);

        for (int i = 0; i < 20; i++) begin
            random_addr_a = $urandom() % MEMORY_DEPTH;
            random_addr_b = $urandom() % MEMORY_DEPTH;
            random_data_a = $urandom();
            random_data_b = $urandom();

            // Avoid collision addresses for this test
            while (random_addr_a == random_addr_b) begin
                random_addr_b = $urandom() % MEMORY_DEPTH;
            end

            // Write from both ports
            write_port_a(random_addr_a, random_data_a);
            write_port_b(random_addr_b, random_data_b);

            // Read back and verify
            read_port_a(random_addr_a);
            check_result_a(random_data_a, $sformatf("Random test %0d Port A", i));

            read_port_b(random_addr_b);
            check_result_b(random_data_b, $sformatf("Random test %0d Port B", i));
        end
    endtask

    // Main test sequence
    initial begin
        $dumpfile("sim/waves/tdpram_tb.vcd");
        $dumpvars(0, tdpram_tb);

        $display("=== TDPRAM Testbench Started ===");
        $display("Configuration: DATA_WIDTH=%0d, ADDR_WIDTH=%0d, DEPTH=%0d",
                 DATA_WIDTH_A, ADDR_WIDTH_A, MEMORY_DEPTH);

        reset_system();

        // Run all tests
        test_basic_operations();
        test_write_collisions();
        test_simultaneous_writes();
        test_read_during_write();
        test_boundary_addresses();
        test_random_operations();

        // Final statistics
        $display("\n=== Test Results Summary ===");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("Success Rate: %0.1f%%", (pass_count * 100.0) / test_count);

        if (fail_count == 0) begin
            $display("*** ALL TESTS PASSED! TDPRAM module is working correctly ***");
        end else begin
            $display("*** %0d TESTS FAILED! Check the failures above ***", fail_count);
        end

        #100;
        $finish;
    end

    // Timeout protection
    initial begin
        #100000;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule