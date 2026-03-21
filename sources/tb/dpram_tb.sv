// Dual Port RAM Testbench - Comprehensive validation with collision testing
// Tests independent port operations, collision detection, and write modes
// Self-checking with detailed pass/fail reporting

`timescale 1ns / 1ps

module dpram_tb;

    // Test parameters
    localparam DATA_WIDTH   = 32;
    localparam ADDR_WIDTH   = 8;
    localparam MEMORY_DEPTH = 2**ADDR_WIDTH;
    localparam CLK_PERIOD   = 10;    // 100MHz clock

    // DUT signals
    logic                     clka;
    logic                     rsta, rstb;
    logic                     ena, enb;
    logic                     wea, web;
    logic [ADDR_WIDTH-1:0]   addra;
    logic [ADDR_WIDTH-1:0]   addrb;
    logic [DATA_WIDTH-1:0]   dina;
    logic [DATA_WIDTH-1:0]   dinb;
    logic [DATA_WIDTH-1:0]   douta;
    logic [DATA_WIDTH-1:0]   doutb;

    // Test control
    logic [DATA_WIDTH-1:0] memory_model [0:MEMORY_DEPTH-1];
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    string current_test = "";

    // Clock generation
    initial begin
        clka = 0;
        forever #(CLK_PERIOD/2) clka = ~clka;
    end

    // DUT instantiation
    dpram #(
        .DATA_WIDTH   (DATA_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .WRITE_MODE_A ("read_first"),
        .WRITE_MODE_B ("read_first"),
        .USE_MEM_INIT (0),
        .MESSAGE_CONTROL(1)
    ) dut (
        .clka (clka),
        .rsta (rsta), .rstb (rstb),
        .ena  (ena),  .enb  (enb),
        .wea  (wea),  .web  (web),
        .addra(addra),.addrb(addrb),
        .dina (dina), .dinb (dinb),
        .douta(douta),.doutb(doutb)
    );

    // Test procedures
    task automatic reset_system();
        rsta = 1; rstb = 1;
        ena = 0; enb = 0;
        wea = 0; web = 0;
        addra = 0; addrb = 0;
        dina = 0; dinb = 0;
        repeat(3) @(posedge clka);
        rsta = 0; rstb = 0;
        repeat(2) @(posedge clka);
        $display("[INFO] System reset completed");
    endtask

    task automatic write_port_a(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
        @(posedge clka);
        ena = 1; wea = 1;
        addra = addr; dina = data;
        @(posedge clka);
        wea = 0;
        memory_model[addr] = data;
    endtask

    task automatic write_port_b(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
        @(posedge clka);
        enb = 1; web = 1;
        addrb = addr; dinb = data;
        @(posedge clka);
        web = 0;
        memory_model[addr] = data;
    endtask

    task automatic read_port_a(input [ADDR_WIDTH-1:0] addr);
        @(posedge clka);
        ena = 1; wea = 0;
        addra = addr;
        @(posedge clka); // Wait for registered output
    endtask

    task automatic read_port_b(input [ADDR_WIDTH-1:0] addr);
        @(posedge clka);
        enb = 1; web = 0;
        addrb = addr;
        @(posedge clka); // address presented to RAM
        @(posedge clka); // registered output now stable
    endtask

    task automatic check_result_a(input [DATA_WIDTH-1:0] expected, input string test_name);
        test_count++;
        if (douta === expected) begin
            pass_count++;
            $display("[PASS] %s (Port A): Expected=0x%08x, Got=0x%08x", test_name, expected, douta);
        end else begin
            fail_count++;
            $display("[FAIL] %s (Port A): Expected=0x%08x, Got=0x%08x", test_name, expected, douta);
        end
    endtask

    task automatic check_result_b(input [DATA_WIDTH-1:0] expected, input string test_name);
        test_count++;
        if (doutb === expected) begin
            pass_count++;
            $display("[PASS] %s (Port B): Expected=0x%08x, Got=0x%08x", test_name, expected, doutb);
        end else begin
            fail_count++;
            $display("[FAIL] %s (Port B): Expected=0x%08x, Got=0x%08x", test_name, expected, doutb);
        end
    endtask

    // Test independent port operations
    task automatic test_independent_operations();
        current_test = "Independent Port Operations";
        $display("\n=== %s Test ===", current_test);

        // Write different data to different addresses from each port
        write_port_a(8'h10, 32'hAAAAAAAA);
        write_port_b(8'h20, 32'hBBBBBBBB);

        // Read back from both ports
        read_port_a(8'h10);
        check_result_a(32'hAAAAAAAA, "Port A independent write/read");

        read_port_b(8'h20);
        check_result_b(32'hBBBBBBBB, "Port B independent write/read");

        // Cross-port reading (A reads what B wrote, B reads what A wrote)
        read_port_a(8'h20);
        check_result_a(32'hBBBBBBBB, "Port A reads Port B data");

        read_port_b(8'h10);
        check_result_b(32'hAAAAAAAA, "Port B reads Port A data");
    endtask

    // Test collision scenarios
    task automatic test_collision_detection();
        current_test = "Collision Detection";
        $display("\n=== %s Test ===", current_test);

        // Simultaneous write to same address - should cause collision
        $display("[INFO] Testing write collision (Port A should win)");
        @(posedge clka);
        ena = 1; enb = 1;
        wea = 1; web = 1;
        addra = 8'h30; addrb = 8'h30;
        dina = 32'hAAAA0000; dinb = 32'hBBBB1111;
        @(posedge clka);
        wea = 0; web = 0;

        // Read back to see which port won
        read_port_a(8'h30);
        check_result_a(32'hAAAA0000, "Collision resolution - Port A wins");

        read_port_b(8'h30);
        check_result_b(32'hAAAA0000, "Collision resolution - Port B sees Port A data");
    endtask

    // Test simultaneous read/write
    task automatic test_read_write_operations();
        current_test = "Simultaneous Read/Write";
        $display("\n=== %s Test ===", current_test);

        // Write from port A, read from port B simultaneously
        write_port_a(8'h40, 32'h12345678);

        @(posedge clka);
        ena = 1; enb = 1;
        wea = 1; web = 0;  // A writes, B reads
        addra = 8'h50; addrb = 8'h40;
        dina = 32'h87654321;
        @(posedge clka);
        wea = 0;

        check_result_b(32'h12345678, "Port B reads while Port A writes elsewhere");

        // Verify port A write completed
        read_port_a(8'h50);
        check_result_a(32'h87654321, "Port A write during simultaneous read/write");
    endtask

    // Test address boundary conditions
    task automatic test_boundary_addresses();
        current_test = "Boundary Address Testing";
        $display("\n=== %s Test ===", current_test);

        // Test minimum and maximum addresses from both ports
        write_port_a(8'h00, 32'h00000001);
        write_port_b(8'hFF, 32'hFFFFFFFE);

        read_port_a(8'h00);
        check_result_a(32'h00000001, "Port A minimum address");

        read_port_b(8'hFF);
        check_result_b(32'hFFFFFFFE, "Port B maximum address");

        // Cross-read boundary addresses
        read_port_a(8'hFF);
        check_result_a(32'hFFFFFFFE, "Port A reads max address");

        read_port_b(8'h00);
        check_result_b(32'h00000001, "Port B reads min address");
    endtask

    // Test enable functionality
    task automatic test_enable_control();
        current_test = "Enable Control";
        $display("\n=== %s Test ===", current_test);

        // Write with port A enabled
        write_port_a(8'h60, 32'h60606060);

        // Try to write with port B disabled
        @(posedge clka);
        enb = 0;  // Disable port B
        web = 1;
        addrb = 8'h60;
        dinb = 32'hBADBADBA;
        @(posedge clka);

        // Read back - should still have port A data
        enb = 1; web = 0;
        read_port_b(8'h60);
        check_result_b(32'h60606060, "Port B disabled write test");
    endtask

    // Test data integrity across multiple operations
    task automatic test_data_integrity();
        current_test = "Data Integrity";
        $display("\n=== %s Test ===", current_test);

        // Fill memory with pattern from both ports
        for (int i = 0; i < 16; i++) begin
            if (i % 2 == 0) begin
                write_port_a(i, 32'h10000000 + i);
            end else begin
                write_port_b(i, 32'h20000000 + i);
            end
        end

        // Verify all data from both ports
        for (int i = 0; i < 16; i++) begin
            logic [31:0] expected = (i % 2 == 0) ? (32'h10000000 + i) : (32'h20000000 + i);

            read_port_a(i);
            check_result_a(expected, $sformatf("Data integrity A addr %0d", i));

            read_port_b(i);
            check_result_b(expected, $sformatf("Data integrity B addr %0d", i));
        end
    endtask

    // Test random operations
    task automatic test_random_operations();
        logic [DATA_WIDTH-1:0] random_data;
        logic [ADDR_WIDTH-1:0] random_addr;
        logic use_port_a;

        current_test = "Random Operations";
        $display("\n=== %s Test ===", current_test);

        for (int i = 0; i < 20; i++) begin
            random_addr = $urandom() % MEMORY_DEPTH;
            random_data = $urandom();
            use_port_a = $urandom() % 2;

            if (use_port_a) begin
                write_port_a(random_addr, random_data);
                read_port_a(random_addr);
                check_result_a(random_data, $sformatf("Random test %0d (Port A)", i));
            end else begin
                write_port_b(random_addr, random_data);
                read_port_b(random_addr);
                check_result_b(random_data, $sformatf("Random test %0d (Port B)", i));
            end
        end
    endtask

    // Test reset behavior
    task automatic test_reset_behavior();
        current_test = "Reset Behavior";
        $display("\n=== %s Test ===", current_test);

        // Write some data
        write_port_a(8'h70, 32'h70707070);
        write_port_b(8'h80, 32'h80808080);

        // Apply reset
        reset_system();

        // Memory should retain data
        read_port_a(8'h70);
        check_result_a(32'h70707070, "Memory retention after reset (Port A)");

        read_port_b(8'h80);
        check_result_b(32'h80808080, "Memory retention after reset (Port B)");
    endtask

    // Main test sequence
    initial begin
        $display("=== DPRAM Testbench Started ===");
        $display("Configuration: DATA_WIDTH=%0d, ADDR_WIDTH=%0d, DEPTH=%0d",
                 DATA_WIDTH, ADDR_WIDTH, MEMORY_DEPTH);

        // Initialize memory model
        for (int i = 0; i < MEMORY_DEPTH; i++) begin
            memory_model[i] = 32'h00000000;
        end

        reset_system();

        // Run all tests
        test_independent_operations();
        test_collision_detection();
        test_read_write_operations();
        test_boundary_addresses();
        test_enable_control();
        test_data_integrity();
        test_random_operations();
        test_reset_behavior();

        // Final statistics
        $display("\n=== Test Results Summary ===");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("Success Rate: %0.1f%%", (pass_count * 100.0) / test_count);

        if (fail_count == 0) begin
            $display("*** ALL TESTS PASSED! DPRAM module is working correctly ***");
        end else begin
            $display("*** %0d TESTS FAILED! Check the failures above ***", fail_count);
        end

        #100;
        $finish;
    end

    // Timeout protection
    initial begin
        #200000; // 200us timeout
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule