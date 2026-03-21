// DPROM Testbench - XPM_MEMORY_DPROM Compatible Validation
// Comprehensive test suite for Dual Port ROM module
// Tests both ports for read-only access with configurable read latency

`timescale 1ns / 1ps

module dprom_tb;

    // Test parameters
    localparam ADDR_WIDTH_A = 6;
    localparam ADDR_WIDTH_B = 6;
    localparam READ_DATA_WIDTH_A = 32;
    localparam READ_DATA_WIDTH_B = 32;
    localparam MEMORY_SIZE = 2048;
    localparam MEMORY_DEPTH_A = MEMORY_SIZE / READ_DATA_WIDTH_A;
    localparam MEMORY_DEPTH_B = MEMORY_SIZE / READ_DATA_WIDTH_B;
    localparam READ_LATENCY_A = 2;
    localparam READ_LATENCY_B = 1;
    localparam RST_MODE_A = "SYNC";
    localparam RST_MODE_B = "SYNC";

    // Clock and reset
    logic clka, clkb;
    logic rsta, rstb;

    // Port A interface (Read-only)
    logic ena;
    logic regcea;
    logic [ADDR_WIDTH_A-1:0] addra;
    logic [READ_DATA_WIDTH_A-1:0] douta;

    // Port B interface (Read-only)
    logic enb;
    logic regceb;
    logic [ADDR_WIDTH_B-1:0] addrb;
    logic [READ_DATA_WIDTH_B-1:0] doutb;

    // Power management and ECC
    logic sleep;
    logic sbiterra, dbiterra, sbiterrb, dbiterrb;
    logic injectsbiterra, injectdbiterra, injectsbiterrb, injectdbiterrb;

    // Test control
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    // Expected data for validation
    logic [READ_DATA_WIDTH_A-1:0] expected_data_a;
    logic [READ_DATA_WIDTH_B-1:0] expected_data_b;

    // Test ROM contents (we'll populate these through direct memory access)
    logic [READ_DATA_WIDTH_A-1:0] test_rom_data [64];

    // Initialize test ROM data
    initial begin
        test_rom_data[0]  = 32'h00000000; test_rom_data[1]  = 32'h11111111; test_rom_data[2]  = 32'h22222222; test_rom_data[3]  = 32'h33333333;
        test_rom_data[4]  = 32'h44444444; test_rom_data[5]  = 32'h55555555; test_rom_data[6]  = 32'h66666666; test_rom_data[7]  = 32'h77777777;
        test_rom_data[8]  = 32'h88888888; test_rom_data[9]  = 32'h99999999; test_rom_data[10] = 32'hAAAAAAAA; test_rom_data[11] = 32'hBBBBBBBB;
        test_rom_data[12] = 32'hCCCCCCCC; test_rom_data[13] = 32'hDDDDDDDD; test_rom_data[14] = 32'hEEEEEEEE; test_rom_data[15] = 32'hFFFFFFFF;
        test_rom_data[16] = 32'h12345678; test_rom_data[17] = 32'h87654321; test_rom_data[18] = 32'hDEADBEEF; test_rom_data[19] = 32'hCAFEBABE;
        test_rom_data[20] = 32'hFEEDFACE; test_rom_data[21] = 32'hDEADC0DE; test_rom_data[22] = 32'hBEEFCAFE; test_rom_data[23] = 32'hFACEFEED;
        test_rom_data[24] = 32'h10203040; test_rom_data[25] = 32'h50607080; test_rom_data[26] = 32'h90A0B0C0; test_rom_data[27] = 32'hD0E0F000;
        test_rom_data[28] = 32'h0F0E0D0C; test_rom_data[29] = 32'h0B0A0908; test_rom_data[30] = 32'h07060504; test_rom_data[31] = 32'h03020100;

        // Fill remaining with zeros
        for (int i = 32; i < 64; i++) begin
            test_rom_data[i] = 32'h00000000;
        end
    end

    // Random test addresses
    int random_addresses_a[10] = '{15, 3, 8, 1, 12, 6, 9, 2, 14, 5};
    int random_addresses_b[10] = '{7, 11, 4, 13, 0, 10, 1, 8, 6, 15};

    // DUT instantiation
    dprom #(
        .ADDR_WIDTH_A(ADDR_WIDTH_A),
        .ADDR_WIDTH_B(ADDR_WIDTH_B),
        .READ_DATA_WIDTH_A(READ_DATA_WIDTH_A),
        .READ_DATA_WIDTH_B(READ_DATA_WIDTH_B),
        .MEMORY_SIZE(MEMORY_SIZE),
        .READ_LATENCY_A(READ_LATENCY_A),
        .READ_LATENCY_B(READ_LATENCY_B),
        .RST_MODE_A(RST_MODE_A),
        .RST_MODE_B(RST_MODE_B),
        .MEMORY_INIT_FILE("none"),
        .IGNORE_INIT_SYNTH(0)
    ) dut (
        .clka(clka),
        .rsta(rsta),
        .rstb(rstb),
        .ena(ena),
        .enb(enb),
        .regcea(regcea),
        .regceb(regceb),
        .addra(addra),
        .addrb(addrb),
        .douta(douta),
        .doutb(doutb),
        .sleep(sleep),
        .sbiterra(sbiterra),
        .dbiterra(dbiterra),
        .sbiterrb(sbiterrb),
        .dbiterrb(dbiterrb),
        .injectsbiterra(injectsbiterra),
        .injectdbiterra(injectdbiterra),
        .injectsbiterrb(injectsbiterrb),
        .injectdbiterrb(injectdbiterrb)
    );

    // Clock generation - common clock
    initial begin
        clka = 0;
        forever #5 clka = ~clka;
    end
    assign clkb = clka;

    // Initialize ROM content through backdoor access
    initial begin
        // Wait a bit for DUT to initialize
        #10;

        // Load test data into ROM memory via backdoor
        for (int i = 0; i < 64; i++) begin
            dut.rom_memory[i] = test_rom_data[i];
        end

        $display("DPROM: Backdoor loaded %0d test patterns into ROM", 64);
    end

    // Test stimulus
    initial begin
        $display("Starting DPROM XPM Compatibility Test Suite");
        $display("==========================================");

        // Initialize signals
        rsta = 1;
        rstb = 1;
        ena = 0;
        enb = 0;
        regcea = 1;
        regceb = 1;
        addra = 0;
        addrb = 0;
        sleep = 0;
        injectsbiterra = 0;
        injectdbiterra = 0;
        injectsbiterrb = 0;
        injectdbiterrb = 0;

        // Wait for reset
        repeat(10) @(posedge clka);
        repeat(10) @(posedge clkb);
        rsta = 0;
        rstb = 0;
        repeat(5) @(posedge clka);
        repeat(5) @(posedge clkb);

        // Wait for ROM initialization
        repeat(5) @(posedge clka);

        // Test 1: Basic Port A read operations
        test_basic_port_a_reads();

        // Test 2: Basic Port B read operations
        test_basic_port_b_reads();

        // Test 3: Simultaneous dual-port reads
        test_simultaneous_dual_reads();

        // Test 4: Reset behavior for both ports
        test_reset_behavior();

        // Test 5: Enable control testing
        test_enable_control();

        // Test 6: Register clock enable (regcea/regceb) control
        test_regce_control();

        // Test 7: Address boundary testing
        test_address_boundaries();

        // Test 8: ECC interface validation
        test_ecc_interface();

        // Test 9: Sequential address pattern testing
        test_sequential_pattern();

        // Test 10: Random access pattern testing
        test_random_access();

        // Test 11: Independent clock domain testing
        test_independent_clocks();

        // Test 12: ROM data integrity verification
        test_rom_data_integrity();

        // Final results
        $display("\n====================================================");
        $display("DPROM Test Results:");
        $display("Total Tests: %0d", test_count);
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);

        if (fail_count == 0) begin
            $display("✅ ALL TESTS PASSED - DPROM XMP Compatible!");
        end else begin
            $display("❌ SOME TESTS FAILED");
        end
        $display("====================================================");

        $finish;
    end

    // Test 1: Basic Port A read operations
    task test_basic_port_a_reads();
        $display("\nTest 1: Basic Port A Read Operations");
        $display("------------------------------------");

        ena = 1;
        regcea = 1;

        // Read first 16 test patterns from Port A
        for (int addr = 0; addr < 16; addr++) begin
            test_single_read_a(addr, test_rom_data[addr], $sformatf("Port A read addr=%0d", addr));
        end
    endtask

    // Test 2: Basic Port B read operations
    task test_basic_port_b_reads();
        $display("\nTest 2: Basic Port B Read Operations");
        $display("------------------------------------");

        enb = 1;
        regceb = 1;

        // Read first 16 test patterns from Port B
        for (int addr = 0; addr < 16; addr++) begin
            test_single_read_b(addr, test_rom_data[addr], $sformatf("Port B read addr=%0d", addr));
        end
    endtask

    // Test 3: Simultaneous dual-port reads
    task test_simultaneous_dual_reads();
        $display("\nTest 3: Simultaneous Dual-Port Reads");
        $display("------------------------------------");

        ena = 1; enb = 1;
        regcea = 1; regceb = 1;

        // Test simultaneous reads from different addresses
        for (int i = 0; i < 8; i++) begin
            addra = i;
            addrb = i + 8;

            fork
                begin
                    repeat(READ_LATENCY_A + 1) @(posedge clka);
                    check_result(douta == test_rom_data[i], $sformatf("Simultaneous Port A addr=%0d", i),
                                $sformatf("Expected 0x%h, got 0x%h", test_rom_data[i], douta));
                end
                begin
                    repeat(READ_LATENCY_B + 1) @(posedge clkb);
                    check_result(doutb == test_rom_data[i + 8], $sformatf("Simultaneous Port B addr=%0d", i + 8),
                                $sformatf("Expected 0x%h, got 0x%h", test_rom_data[i + 8], doutb));
                end
            join
        end
    endtask

    // Test 4: Reset behavior for both ports
    task test_reset_behavior();
        $display("\nTest 4: Reset Behavior");
        $display("----------------------");

        // Setup some reads in progress
        ena = 1; enb = 1;
        regcea = 1; regceb = 1;
        addra = 10; addrb = 10;
        repeat(READ_LATENCY_A + 2) @(posedge clka);
        repeat(READ_LATENCY_B + 2) @(posedge clkb);

        // Apply resets
        rsta = 1; rstb = 1;
        @(posedge clka);
        @(posedge clkb);

        check_result(douta == 0, "Port A reset behavior",
                    $sformatf("Port A douta should be 0 after reset, got 0x%h", douta));
        check_result(doutb == 0, "Port B reset behavior",
                    $sformatf("Port B doutb should be 0 after reset, got 0x%h", doutb));

        rsta = 0; rstb = 0;
        repeat(3) @(posedge clka);
        repeat(3) @(posedge clkb);
    endtask

    // Test 5: Enable control testing
    task test_enable_control();
        $display("\nTest 5: Enable Control");
        $display("----------------------");

        // Test Port A enable control
        ena = 1;
        addra = 20;
        repeat(READ_LATENCY_A + 1) @(posedge clka);
        expected_data_a = douta;

        // Disable Port A and check output behavior
        ena = 0;
        addra = 21; // Change address while disabled
        repeat(3) @(posedge clka);
        check_result(douta == expected_data_a, "Port A enable control",
                    $sformatf("Port A output should remain stable when ena=0, expected=0x%h, got=0x%h",
                             expected_data_a, douta));

        // Test Port B enable control
        enb = 1;
        addrb = 20;
        repeat(READ_LATENCY_B + 1) @(posedge clkb);
        expected_data_b = doutb;

        // Disable Port B and check output behavior
        enb = 0;
        addrb = 21; // Change address while disabled
        repeat(3) @(posedge clkb);
        check_result(doutb == expected_data_b, "Port B enable control",
                    $sformatf("Port B output should remain stable when enb=0, expected=0x%h, got=0x%h",
                             expected_data_b, doutb));
    endtask

    // Test 6: Register clock enable control
    task test_regce_control();
        $display("\nTest 6: Register Clock Enable Control");
        $display("-------------------------------------");

        if (READ_LATENCY_A > 0) begin
            // Test Port A regcea control
            ena = 1; regcea = 1;
            addra = 25;
            repeat(READ_LATENCY_A + 1) @(posedge clka);
            expected_data_a = douta;

            // Change address but disable regcea
            addra = 26;
            regcea = 0;
            repeat(3) @(posedge clka);

            check_result(douta == expected_data_a, "Port A REGCEA control",
                        $sformatf("Port A output should not update when regcea=0, expected=0x%h, got=0x%h",
                                 expected_data_a, douta));
            regcea = 1; // Re-enable
        end

        if (READ_LATENCY_B > 0) begin
            // Test Port B regceb control
            enb = 1; regceb = 1;
            addrb = 25;
            repeat(READ_LATENCY_B + 1) @(posedge clkb);
            expected_data_b = doutb;

            // Change address but disable regceb
            addrb = 26;
            regceb = 0;
            repeat(3) @(posedge clkb);

            check_result(doutb == expected_data_b, "Port B REGCEB control",
                        $sformatf("Port B output should not update when regceb=0, expected=0x%h, got=0x%h",
                                 expected_data_b, doutb));
            regceb = 1; // Re-enable
        end
    endtask

    // Test 7: Address boundary testing
    task test_address_boundaries();
        $display("\nTest 7: Address Boundary Testing");
        $display("--------------------------------");

        ena = 1; enb = 1;
        regcea = 1; regceb = 1;

        // Test first addresses
        test_single_read_a(0, test_rom_data[0], "Port A first address (0)");
        test_single_read_b(0, test_rom_data[0], "Port B first address (0)");

        // Test last valid addresses
        test_single_read_a(MEMORY_DEPTH_A-1, test_rom_data[MEMORY_DEPTH_A-1],
                          $sformatf("Port A last address (%0d)", MEMORY_DEPTH_A-1));
        test_single_read_b(MEMORY_DEPTH_B-1, test_rom_data[MEMORY_DEPTH_B-1],
                          $sformatf("Port B last address (%0d)", MEMORY_DEPTH_B-1));

        // Test middle addresses
        test_single_read_a(MEMORY_DEPTH_A/2, test_rom_data[MEMORY_DEPTH_A/2],
                          $sformatf("Port A middle address (%0d)", MEMORY_DEPTH_A/2));
        test_single_read_b(MEMORY_DEPTH_B/2, test_rom_data[MEMORY_DEPTH_B/2],
                          $sformatf("Port B middle address (%0d)", MEMORY_DEPTH_B/2));
    endtask

    // Test 8: ECC interface validation
    task test_ecc_interface();
        $display("\nTest 8: ECC Interface Validation");
        $display("--------------------------------");

        // ECC outputs should always be 0 (no ECC support)
        repeat(10) @(posedge clka);
        repeat(10) @(posedge clkb);

        check_result(sbiterra == 1'b0, "ECC sbiterra", "sbiterra should always be 0");
        check_result(dbiterra == 1'b0, "ECC dbiterra", "dbiterra should always be 0");
        check_result(sbiterrb == 1'b0, "ECC sbiterrb", "sbiterrb should always be 0");
        check_result(dbiterrb == 1'b0, "ECC dbiterrb", "dbiterrb should always be 0");
    endtask

    // Test 9: Sequential address pattern testing
    task test_sequential_pattern();
        $display("\nTest 9: Sequential Address Pattern Testing");
        $display("------------------------------------------");

        ena = 1; enb = 1;
        regcea = 1; regceb = 1;

        // Sequential reads from Port A then Port B (shared address signals require sequential access)
        for (int addr = 0; addr < 32; addr++) begin
            test_single_read_a(addr, test_rom_data[addr],
                              $sformatf("Port A sequential read %0d", addr));
        end

        for (int addr = 0; addr < 32; addr++) begin
            test_single_read_b(addr, test_rom_data[addr],
                              $sformatf("Port B sequential read %0d", addr));
        end
    endtask

    // Test 10: Random access pattern testing
    task test_random_access();
        $display("\nTest 10: Random Access Pattern Testing");
        $display("--------------------------------------");

        ena = 1; enb = 1;
        regcea = 1; regceb = 1;

        // Random reads from Port A
        foreach (random_addresses_a[i]) begin
            test_single_read_a(random_addresses_a[i], test_rom_data[random_addresses_a[i]],
                              $sformatf("Port A random read %0d (addr=%0d)", i, random_addresses_a[i]));
        end

        // Random reads from Port B
        foreach (random_addresses_b[i]) begin
            test_single_read_b(random_addresses_b[i], test_rom_data[random_addresses_b[i]],
                              $sformatf("Port B random read %0d (addr=%0d)", i, random_addresses_b[i]));
        end
    endtask

    // Test 11: Independent clock domain testing
    task test_independent_clocks();
        $display("\nTest 11: Independent Clock Domain Testing");
        $display("-----------------------------------------");

        ena = 1; enb = 1;
        regcea = 1; regceb = 1;

        // Access different addresses from each port with independent timing
        fork
            begin
                for (int i = 0; i < 5; i++) begin
                    addra = i;
                    repeat(READ_LATENCY_A + 1) @(posedge clka);
                    check_result(douta == test_rom_data[i], $sformatf("Independent clock Port A read %0d", i),
                                $sformatf("Expected 0x%h, got 0x%h", test_rom_data[i], douta));
                    repeat(2) @(posedge clka); // Additional delay
                end
            end
            begin
                for (int i = 5; i < 10; i++) begin
                    addrb = i;
                    repeat(READ_LATENCY_B + 1) @(posedge clkb);
                    check_result(doutb == test_rom_data[i], $sformatf("Independent clock Port B read %0d", i),
                                $sformatf("Expected 0x%h, got 0x%h", test_rom_data[i], doutb));
                    repeat(3) @(posedge clkb); // Different delay
                end
            end
        join
    endtask

    // Test 12: ROM data integrity verification
    task test_rom_data_integrity();
        $display("\nTest 12: ROM Data Integrity Verification");
        $display("----------------------------------------");

        ena = 1; enb = 1;
        regcea = 1; regceb = 1;

        // Verify all loaded ROM data through both ports
        for (int addr = 0; addr < 32; addr++) begin
            // Read from Port A
            addra = addr;
            repeat(READ_LATENCY_A + 1) @(posedge clka);
            check_result(douta == test_rom_data[addr], $sformatf("ROM integrity Port A addr=%0d", addr),
                        $sformatf("Expected 0x%h, got 0x%h", test_rom_data[addr], douta));

            // Read same address from Port B
            addrb = addr;
            repeat(READ_LATENCY_B + 1) @(posedge clkb);
            check_result(doutb == test_rom_data[addr], $sformatf("ROM integrity Port B addr=%0d", addr),
                        $sformatf("Expected 0x%h, got 0x%h", test_rom_data[addr], doutb));
        end
    endtask

    // Helper task: Single read operation from Port A
    task test_single_read_a(input int addr, input logic [READ_DATA_WIDTH_A-1:0] expected, input string test_name);
        addra = addr;
        repeat(READ_LATENCY_A + 1) @(posedge clka);

        check_result(douta == expected, test_name,
                    $sformatf("addr=%0d: expected=0x%h, got=0x%h", addr, expected, douta));
    endtask

    // Helper task: Single read operation from Port B
    task test_single_read_b(input int addr, input logic [READ_DATA_WIDTH_B-1:0] expected, input string test_name);
        addrb = addr;
        repeat(READ_LATENCY_B + 1) @(posedge clkb);

        check_result(doutb == expected, test_name,
                    $sformatf("addr=%0d: expected=0x%h, got=0x%h", addr, expected, doutb));
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
        if (ena && $time > 200ns) begin
            // Optional: Add monitoring logic here
        end
    end

    always @(posedge clkb) begin
        if (enb && $time > 200ns) begin
            // Optional: Add monitoring logic here
        end
    end

    // Timeout protection
    initial begin
        #200000ns;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule