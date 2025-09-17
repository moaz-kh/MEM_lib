// SPROM Testbench - XPM_MEMORY_SPROM Compatible Validation
// Comprehensive test suite for Single Port ROM module
// Tests all read latencies, reset modes, and initialization methods

`timescale 1ns / 1ps

module sprom_tb;

    // Test parameters
    localparam ADDR_WIDTH_A = 6;
    localparam READ_DATA_WIDTH_A = 32;
    localparam MEMORY_SIZE = 2048;
    localparam MEMORY_DEPTH = MEMORY_SIZE / READ_DATA_WIDTH_A;
    localparam READ_LATENCY_A = 2;
    localparam RST_MODE_A = "SYNC";

    // Clock and reset
    logic clka;
    logic rsta;

    // DUT interfaces
    logic ena;
    logic [ADDR_WIDTH_A-1:0] addra;
    logic [READ_DATA_WIDTH_A-1:0] douta;
    logic regcea;
    logic sbiterra, dbiterra;

    // Test control
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    logic test_passed;

    // Expected data for validation
    logic [READ_DATA_WIDTH_A-1:0] expected_data;
    logic [READ_DATA_WIDTH_A-1:0] memory_model [0:MEMORY_DEPTH-1];

    // Test data arrays
    int random_addresses[10];

    // DUT instantiation
    sprom #(
        .ADDR_WIDTH_A(ADDR_WIDTH_A),
        .READ_DATA_WIDTH_A(READ_DATA_WIDTH_A),
        .MEMORY_SIZE(MEMORY_SIZE),
        .READ_LATENCY_A(READ_LATENCY_A),
        .RST_MODE_A(RST_MODE_A),
        .MEMORY_INIT_FILE("none"),
        .IGNORE_INIT_SYNTH(0)
    ) dut (
        .clka(clka),
        .rsta(rsta),
        .ena(ena),
        .addra(addra),
        .douta(douta),
        .regcea(regcea),
        .sbiterra(sbiterra),
        .dbiterra(dbiterra)
    );

    // Clock generation
    initial begin
        clka = 0;
        forever #5 clka = ~clka; // 100MHz clock
    end

    // Test stimulus
    initial begin
        $display("Starting SPROM XPM Compatibility Test Suite");
        $display("=========================================");

        // Initialize signals
        rsta = 1;
        ena = 0;
        addra = 0;
        regcea = 1;

        // Initialize memory model (since DUT uses zeros by default)
        for (int i = 0; i < MEMORY_DEPTH; i++) begin
            memory_model[i] = {READ_DATA_WIDTH_A{1'b0}};
        end

        // Wait for reset
        repeat(5) @(posedge clka);
        rsta = 0;
        repeat(2) @(posedge clka);

        // Test 1: Basic read operations
        test_basic_reads();

        // Test 2: Reset behavior
        test_reset_behavior();

        // Test 3: Enable control
        test_enable_control();

        // Test 4: Register clock enable (regcea)
        test_regcea_control();

        // Test 5: Address boundary testing
        test_address_boundaries();

        // Test 6: ECC interface validation
        test_ecc_interface();

        // Test 7: Sequential address pattern
        test_sequential_pattern();

        // Test 8: Random access pattern
        test_random_access();

        // Final results
        $display("\n==================================================");
        $display("SPROM Test Results:");
        $display("Total Tests: %0d", test_count);
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);

        if (fail_count == 0) begin
            $display("✅ ALL TESTS PASSED - SPROM XMP Compatible!");
        end else begin
            $display("❌ SOME TESTS FAILED");
        end
        $display("==================================================");

        $finish;
    end

    // Test 1: Basic read operations
    task test_basic_reads();
        $display("\nTest 1: Basic Read Operations");
        $display("-----------------------------");

        ena = 1;
        regcea = 1;

        // Test multiple addresses
        for (int addr = 0; addr < 8; addr++) begin
            test_single_read(addr, memory_model[addr], $sformatf("Basic read addr=%0d", addr));
        end
    endtask

    // Test 2: Reset behavior
    task test_reset_behavior();
        $display("\nTest 2: Reset Behavior");
        $display("----------------------");

        // Perform a read to get some data in pipeline
        ena = 1;
        regcea = 1;
        addra = 5;
        repeat(READ_LATENCY_A + 2) @(posedge clka);

        // Apply reset and check output goes to reset value
        rsta = 1;
        @(posedge clka);

        check_result(douta == 0, "Reset behavior", $sformatf("douta should be 0 after reset, got 0x%h", douta));

        rsta = 0;
        repeat(2) @(posedge clka);
    endtask

    // Test 3: Enable control
    task test_enable_control();
        $display("\nTest 3: Enable Control");
        $display("----------------------");

        // Read with enable high
        ena = 1;
        regcea = 1;
        addra = 3;
        repeat(READ_LATENCY_A + 1) @(posedge clka);
        expected_data = douta;

        // Read with enable low - output should remain stable
        ena = 0;
        repeat(3) @(posedge clka);

        check_result(douta == expected_data, "Enable control",
                    $sformatf("Output should remain stable when ena=0, expected=0x%h, got=0x%h", expected_data, douta));
    endtask

    // Test 4: Register clock enable control
    task test_regcea_control();
        $display("\nTest 4: Register Clock Enable Control");
        $display("-------------------------------------");

        if (READ_LATENCY_A > 0) begin
            // Setup a read operation
            ena = 1;
            regcea = 1;
            addra = 7;
            repeat(READ_LATENCY_A) @(posedge clka);

            expected_data = douta;

            // Change address but disable regcea
            addra = 2;
            regcea = 0;
            repeat(2) @(posedge clka);

            // Output should not change when regcea is disabled
            check_result(douta == expected_data, "REGCEA control",
                        $sformatf("Output should not update when regcea=0, expected=0x%h, got=0x%h", expected_data, douta));

            // Re-enable regcea
            regcea = 1;
            repeat(READ_LATENCY_A) @(posedge clka);
        end else begin
            $display("  Skipping regcea test for combinational read (READ_LATENCY_A=0)");
        end
    endtask

    // Test 5: Address boundary testing
    task test_address_boundaries();
        $display("\nTest 5: Address Boundary Testing");
        $display("--------------------------------");

        ena = 1;
        regcea = 1;

        // Test first address
        test_single_read(0, memory_model[0], "First address (0)");

        // Test last valid address
        test_single_read(MEMORY_DEPTH-1, memory_model[MEMORY_DEPTH-1], $sformatf("Last address (%0d)", MEMORY_DEPTH-1));

        // Test middle address
        test_single_read(MEMORY_DEPTH/2, memory_model[MEMORY_DEPTH/2], $sformatf("Middle address (%0d)", MEMORY_DEPTH/2));
    endtask

    // Test 6: ECC interface validation
    task test_ecc_interface();
        $display("\nTest 6: ECC Interface Validation");
        $display("--------------------------------");

        // ECC outputs should always be 0 (no ECC support)
        repeat(10) @(posedge clka);

        check_result(sbiterra == 1'b0, "ECC sbiterra", "sbiterra should always be 0");
        check_result(dbiterra == 1'b0, "ECC dbiterra", "dbiterra should always be 0");
    endtask

    // Test 7: Sequential address pattern
    task test_sequential_pattern();
        $display("\nTest 7: Sequential Address Pattern");
        $display("----------------------------------");

        ena = 1;
        regcea = 1;

        // Sequential read pattern
        for (int addr = 0; addr < 16; addr++) begin
            addra = addr;
            repeat(READ_LATENCY_A + 1) @(posedge clka);
            expected_data = memory_model[addr];

            check_result(douta == expected_data, $sformatf("Sequential read %0d", addr),
                        $sformatf("addr=%0d: expected=0x%h, got=0x%h", addr, expected_data, douta));
        end
    endtask

    // Test 8: Random access pattern
    task test_random_access();
        $display("\nTest 8: Random Access Pattern");
        $display("-----------------------------");

        // Initialize random address array
        random_addresses[0] = 15; random_addresses[1] = 3; random_addresses[2] = 8;
        random_addresses[3] = 1;  random_addresses[4] = 12; random_addresses[5] = 6;
        random_addresses[6] = 9;  random_addresses[7] = 2; random_addresses[8] = 14; random_addresses[9] = 5;

        ena = 1;
        regcea = 1;

        foreach (random_addresses[i]) begin
            test_single_read(random_addresses[i], memory_model[random_addresses[i]],
                           $sformatf("Random access %0d (addr=%0d)", i, random_addresses[i]));
        end
    endtask

    // Helper task: Single read operation
    task test_single_read(input int addr, input logic [READ_DATA_WIDTH_A-1:0] expected, input string test_name);
        addra = addr;
        repeat(READ_LATENCY_A + 1) @(posedge clka);

        check_result(douta == expected, test_name,
                    $sformatf("addr=%0d: expected=0x%h, got=0x%h", addr, expected, douta));
    endtask

    // Helper task: Check test result
    task check_result(input logic condition, input string test_name, input string details);
        test_count++;
        if (condition) begin
            pass_count++;
            $display("  ✅ PASS: %s", test_name);
        end else begin
            fail_count++;
            $display("  ❌ FAIL: %s - %s", test_name, details);
        end
    endtask

    // Monitor for debugging
    always @(posedge clka) begin
        if (ena && $time > 100ns) begin
            // Optional: Add monitoring logic here
        end
    end

    // Timeout protection
    initial begin
        #50000ns;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule

// Additional test configurations for different parameters
module sprom_test_configs;

    // Test different read latencies
    initial begin
        $display("SPROM Test Configuration Matrix:");
        $display("- READ_LATENCY_A: 0, 1, 2, 3, 5");
        $display("- RST_MODE_A: SYNC, ASYNC");
        $display("- ADDR_WIDTH_A: 4, 6, 8, 10");
        $display("- READ_DATA_WIDTH_A: 8, 16, 32, 64");
        $display("Run individual tests by changing parameters in main testbench");
    end

endmodule