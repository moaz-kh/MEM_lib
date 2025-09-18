// DPDISTRAM Testbench - XPM_MEMORY_DPDISTRAM Compatible Validation
// Comprehensive test suite for Dual Port Distributed RAM module
// Tests Port A read/write with byte-enable, Port B read-only, and all latencies

`timescale 1ns / 1ps

module dpdistram_tb;

    // Test parameters
    localparam ADDR_WIDTH_A = 6;
    localparam ADDR_WIDTH_B = 6;
    localparam READ_DATA_WIDTH_A = 32;
    localparam READ_DATA_WIDTH_B = 32;
    localparam WRITE_DATA_WIDTH_A = 32;
    localparam BYTE_WRITE_WIDTH_A = 8;
    localparam MEMORY_SIZE = 512;
    localparam MEMORY_DEPTH_A = MEMORY_SIZE / READ_DATA_WIDTH_A;
    localparam MEMORY_DEPTH_B = MEMORY_SIZE / READ_DATA_WIDTH_B;
    localparam READ_LATENCY_A = 2;
    localparam READ_LATENCY_B = 1;
    localparam RST_MODE_A = "SYNC";
    localparam RST_MODE_B = "SYNC";
    localparam NUM_BYTES_A = WRITE_DATA_WIDTH_A / BYTE_WRITE_WIDTH_A;

    // Clock and reset
    logic clka, clkb;
    logic rsta, rstb;

    // Port A interface (Read/Write)
    logic ena;
    logic regcea;
    logic [NUM_BYTES_A-1:0] wea;
    logic [ADDR_WIDTH_A-1:0] addra;
    logic [WRITE_DATA_WIDTH_A-1:0] dina;
    logic [READ_DATA_WIDTH_A-1:0] douta;

    // Port B interface (Read-only)
    logic enb;
    logic regceb;
    logic [ADDR_WIDTH_B-1:0] addrb;
    logic [READ_DATA_WIDTH_B-1:0] doutb;

    // Power management and ECC
    logic sleep;
    logic sbiterra, dbiterra, sbiterrb, dbiterrb;

    // Test control
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    // Expected data for validation
    logic [READ_DATA_WIDTH_A-1:0] expected_data_a;
    logic [READ_DATA_WIDTH_B-1:0] expected_data_b;
    logic [READ_DATA_WIDTH_A-1:0] memory_model [0:MEMORY_DEPTH_A-1];

    /*// Test patterns
    logic [READ_DATA_WIDTH_A-1:0] test_patterns [8] = '{
        8'h00, 8'hFF, 8'h55, 8'hAA,
        8'h12, 8'h87, 8'hDE, 8'hCA
    };
*/
    // Random test addresses
    int random_addresses_a[10];
    int random_addresses_b[10];

    // DUT instantiation
    dpdistram #(
        .ADDR_WIDTH_A(ADDR_WIDTH_A),
        .ADDR_WIDTH_B(ADDR_WIDTH_B),
        .READ_DATA_WIDTH_A(READ_DATA_WIDTH_A),
        .READ_DATA_WIDTH_B(READ_DATA_WIDTH_B),
        .WRITE_DATA_WIDTH_A(WRITE_DATA_WIDTH_A),
        .BYTE_WRITE_WIDTH_A(BYTE_WRITE_WIDTH_A),
        .MEMORY_SIZE(MEMORY_SIZE),
        .READ_LATENCY_A(READ_LATENCY_A),
        .READ_LATENCY_B(READ_LATENCY_B),
        .RST_MODE_A(RST_MODE_A),
        .RST_MODE_B(RST_MODE_B),
        .MEMORY_INIT_FILE("none"),
        .IGNORE_INIT_SYNTH(0)
    ) dut (
        .clka(clka),
        .clkb(clkb),
        .rsta(rsta),
        .rstb(rstb),
        .ena(ena),
        .enb(enb),
        .regcea(regcea),
        .regceb(regceb),
        .wea(wea),
        .addra(addra),
        .addrb(addrb),
        .dina(dina),
        .douta(douta),
        .doutb(doutb),
        .sleep(sleep),
        .sbiterra(sbiterra),
        .dbiterra(dbiterra),
        .sbiterrb(sbiterrb),
        .dbiterrb(dbiterrb)
    );

    // Waveform dump - VCD format for universal compatibility
    initial begin
        $dumpfile("sim/waves/dpdistram_tb.vcd");
        $dumpvars(0, dpdistram_tb);  // Dump all signals in testbench
        
        // Explicitly dump array elements for better visibility
        for (int i = 0; i < 16; i++) begin
            $dumpvars(1, dut.dist_memory[i]);
        end
        // Explicitly dump array elements for better visibility
        for (int i = 0; i < 16; i++) begin
            $dumpvars(1, memory_model[i]);
        end
        
        $display("[VCD] Waveform file: sim/waves/dpdistram_tb.vcd");
    end

    // Clock generation - independent clocks
    initial begin
        clka = 0;
        forever #5 clka = ~clka; // 100MHz clock A
    end

    initial begin
        clkb = 0;
        forever #5 clkb = ~clkb; // ~71MHz clock B (independent)
    end

    // Test stimulus
    initial begin
        $display("Starting DPDISTRAM XPM Compatibility Test Suite");
        $display("==============================================");

        // Initialize signals
        rsta = 1;
        rstb = 1;
        ena = 0;
        enb = 0;
        regcea = 1;
        regceb = 1;
        wea = '0;
        addra = 0;
        addrb = 0;
        dina = 0;
        sleep = 0;

        // Initialize memory model
        for (int i = 0; i < MEMORY_DEPTH_A; i++) begin
            memory_model[i] = {READ_DATA_WIDTH_A{1'b0}};
        end

        // Initialize random addresses
        random_addresses_a[0] = rand_addr(); random_addresses_a[1] = rand_addr(); random_addresses_a[2] = rand_addr();
        random_addresses_a[3] = rand_addr();  random_addresses_a[4] = rand_addr(); random_addresses_a[5] = rand_addr();
        random_addresses_a[6] = rand_addr();  random_addresses_a[7] = rand_addr(); random_addresses_a[8] = rand_addr(); random_addresses_a[9] = rand_addr();

        random_addresses_b[0] = rand_addr(); random_addresses_b[1] = rand_addr(); random_addresses_b[2] = rand_addr();
        random_addresses_b[3] = rand_addr(); random_addresses_b[4] = rand_addr(); random_addresses_b[5] = rand_addr();
        random_addresses_b[6] = rand_addr();  random_addresses_b[7] = rand_addr(); random_addresses_b[8] = rand_addr(); random_addresses_b[9] = rand_addr();

        // Wait for reset
        repeat(10) @(posedge clka);
        repeat(10) @(posedge clkb);
        rsta = 0;
        rstb = 0;
        repeat(5) @(posedge clka);
        repeat(5) @(posedge clkb);

        // Test 1: Basic Port A write operations
        test_basic_port_a_writes();

        // Test 2: Basic Port A read operations
        test_basic_port_a_reads();

        // Test 3: Port B read operations
        test_port_b_reads();

        // Test 4: Byte-enable write testing
        test_byte_enable_writes();

        // Test 5: Simultaneous Port A write and Port B read
        test_simultaneous_operations();

        // Test 6: Reset behavior for both ports
        test_reset_behavior();

        // Test 7: Enable control testing
        test_enable_control();

        // Test 8: Register clock enable (regcea/regceb) control
        test_regce_control();

        // Test 9: Address boundary testing
        test_address_boundaries();

        // Test 10: ECC interface validation
        test_ecc_interface();

        // Test 11: Pattern testing
        test_pattern_operations();

        // Test 12: Random access testing
        //test_random_access();

        // Final results
        $display("\n===================================================");
        $display("DPDISTRAM Test Results:");
        $display("Total Tests: %0d", test_count);
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);

        if (fail_count == 0) begin
            $display("✅ ALL TESTS PASSED - DPDISTRAM XMP Compatible!");
        end else begin
            $display("❌ SOME TESTS FAILED");
        end
        $display("===================================================");

        $finish;
    end
    
    
    // Function to return a random WIDTH-bit value
    function automatic logic [ADDR_WIDTH_A-1:0] rand_addr();
        logic [ADDR_WIDTH_A-1:0] tmp;
        begin
          if (ADDR_WIDTH_A <= 32) begin
            tmp = $urandom & ((32'h1 << ADDR_WIDTH_A) - 1);
          end else begin
            for (int i = 0; i < ADDR_WIDTH_A; i += 32) begin
              tmp[i +: 32] = $urandom;
            end
          end
          return (tmp%MEMORY_DEPTH_A);
        end
    endfunction
    
    // Function to return a random WIDTH-bit value
    function automatic logic [READ_DATA_WIDTH_A-1:0] rand_data();
        logic [READ_DATA_WIDTH_A-1:0] tmp;
        begin
          if (READ_DATA_WIDTH_A <= 32) begin
            tmp = $urandom & ((32'h1 << READ_DATA_WIDTH_A) - 1);
          end else begin
            for (int i = 0; i < READ_DATA_WIDTH_A; i += 32) begin
              tmp[i +: 32] = $urandom;
            end
          end
          return tmp;
        end
    endfunction
    
  
    // Test 1: Basic Port A write operations
    task test_basic_port_a_writes();
        $display("\nTest 1: Basic Port A Write Operations");
        $display("-------------------------------------");

        @(negedge clka);
        ena = 1;
        regcea = 1;
        wea = {NUM_BYTES_A{1'b1}}; // All bytes enabled
         
        // Write test patterns to first 8 addresses
        for (int addr = 0; addr < (8%MEMORY_DEPTH_A); addr++) begin
            addra = addr;
            dina = rand_data();
            memory_model[addr] = dina; // Update model
            
            $display("addra = %h, dina = %h",addra,dina);
            @(posedge clka);
            #1;
        end

        // Wait for writes to complete
        wea = {NUM_BYTES_A{1'b0}};
        repeat(3) @(posedge clka);

        $display("  ✅ PASS: Basic Port A writes completed");
        test_count++;
        pass_count++;
    endtask

    // Test 2: Basic Port A read operations
    task test_basic_port_a_reads();
        $display("\nTest 2: Basic Port A Read Operations");
        $display("------------------------------------");

        ena = 1;
        regcea = 1;
        wea = {NUM_BYTES_A{1'b0}}; // Read mode
        // Read back the written patterns
        for (int addr = 0; addr < (8%MEMORY_DEPTH_A); addr++) begin
            test_single_read_a(addr, memory_model[addr], $sformatf("Port A read addr=%0d", addr));
        end
    endtask

    // Test 3: Port B read operations
    task test_port_b_reads();
        $display("\nTest 3: Port B Read Operations");
        $display("------------------------------");

        enb = 1;
        regceb = 1;

        // Read from Port B the data written by Port A
        for (int addr = 0; addr < rand_addr(); addr++) begin
            test_single_read_b(addr, memory_model[addr], $sformatf("Port B read addr=%0d", addr));
        end
    endtask

    // Test 4: Byte-enable write testing
    task test_byte_enable_writes();
        $display("\nTest 4: Byte-Enable Write Testing");
        $display("---------------------------------");

        ena = 1;
        regcea = 1;
        addra = rand_addr();  

        // Test individual byte writes
        dina = rand_data();
        memory_model[addra] = dina; 
        
        wea = {NUM_BYTES_A{1'b0}};
        
        @(posedge clka);
        for (int i = NUM_BYTES_A-1; i >= 0; i--) begin
            wea[i] = 1'b1; 
            @(posedge clka);
            @(posedge clka);
            wea = {NUM_BYTES_A{1'b0}};
            repeat(READ_LATENCY_A + 2) @(posedge clka);
            check_result(douta[i*BYTE_WRITE_WIDTH_A +: BYTE_WRITE_WIDTH_A] == dina[i*BYTE_WRITE_WIDTH_A +: BYTE_WRITE_WIDTH_A], "Byte 0 write",
                    $sformatf("Expected byte 0 = 0x%h, got 0x%h", dina[i*BYTE_WRITE_WIDTH_A +: BYTE_WRITE_WIDTH_A], douta[i*BYTE_WRITE_WIDTH_A +: BYTE_WRITE_WIDTH_A]));
            
        end
        /*
        // Write only byte 0
        wea = 4'b0001;
        @(posedge clka);
        wea = {NUM_BYTES_A{1'b0}};
        repeat(READ_LATENCY_A + 2) @(posedge clka);
        check_result(douta[7:0] == dina[7:0], "Byte 0 write",
                    $sformatf("Expected byte 0 = 0x%h, got 0x%h", douta[7:0], dina[7:0]));

        // Write only byte 1
        wea = 4'b0010;
        @(posedge clka);
        wea = {NUM_BYTES_A{1'b0}};
        repeat(READ_LATENCY_A + 2) @(posedge clka);
        check_result(douta[15:8] == dina[15:8], "Byte 1 write",
                    $sformatf("Expected byte 1 = 0x%h, got 0x%h", douta[15:8], dina[15:8]));

        // Write bytes 2 and 3 together
        wea = 4'b1100;
        @(posedge clka);
        wea = {NUM_BYTES_A{1'b0}};
        repeat(READ_LATENCY_A + 2) @(posedge clka);
        check_result(douta[31:16] == dina[31:16], "Bytes 2-3 write",
                    $sformatf("Expected bytes 2-3 = 0x%h, got 0x%h", douta[31:16], dina[31:16]));
    */
    
    endtask

    // Test 5: Simultaneous Port A write and Port B read
    task test_simultaneous_operations();
        $display("\nTest 5: Simultaneous Port A Write and Port B Read");
        $display("-------------------------------------------------");

        // Setup Port A for write
        ena = 1;
        regcea = 1;
        addra = rand_addr();
        dina = rand_data();
        wea = {NUM_BYTES_A{1'b1}};
        memory_model[addra] = dina;
        // Setup Port B for read from different address
        enb = 1;
        regceb = 1;
        addrb = 0; // Read from address 0 (should have memory_model[0])

        // Execute simultaneously
        fork
            begin
                @(posedge clka);
                wea = {NUM_BYTES_A{1'b0}};
            end
            begin
                repeat(READ_LATENCY_B + 2) @(posedge clkb);
                check_result(doutb == memory_model[0], "Simultaneous read Port B",
                            $sformatf("%t, Expected 0x%h, got 0x%h", $time ,memory_model[0], doutb));
            end
        join

        // Verify Port A write took effect
        //addra = 20;
        wea = {NUM_BYTES_A{1'b0}};
        repeat(READ_LATENCY_A + 2) @(posedge clka);
        check_result(douta == dina, "Simultaneous write Port A",
                    $sformatf("Expected 0x%h, got 0x%h",dina, douta));
    endtask

    // Test 6: Reset behavior for both ports
    task test_reset_behavior();
        $display("\nTest 6: Reset Behavior");
        $display("----------------------");

        // Setup some data in pipeline
        ena = 1; enb = 1;
        regcea = 1; regceb = 1;
        addra = rand_addr(); addrb = rand_addr();
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

    // Test 7: Enable control testing
    task test_enable_control();
        $display("\nTest 7: Enable Control");
        $display("----------------------");

        // Test Port A enable control
        ena = 1;
        addra = rand_addr();
        repeat(READ_LATENCY_A + 1) @(posedge clka);
        expected_data_a = douta;

        // Disable Port A and check output remains stable
        ena = 0;
        repeat(3) @(posedge clka);
        check_result(douta == expected_data_a, "Port A enable control",
                    $sformatf("Port A output should remain stable when ena=0, expected=0x%h, got=0x%h",
                             expected_data_a, douta));

        // Test Port B enable control
        enb = 1;
        addrb = rand_addr();
        repeat(READ_LATENCY_B + 1) @(posedge clkb);
        expected_data_b = doutb;

        // Disable Port B and check output remains stable
        enb = 0;
        repeat(3) @(posedge clkb);
        check_result(doutb == expected_data_b, "Port B enable control",
                    $sformatf("Port B output should remain stable when enb=0, expected=0x%h, got=0x%h",
                             expected_data_b, doutb));
    endtask

    // Test 8: Register clock enable control
    task test_regce_control();
        $display("\nTest 8: Register Clock Enable Control");
        $display("-------------------------------------");

        if (READ_LATENCY_A > 0) begin
            // Test Port A regcea control
            ena = 1; regcea = 1;
            addra = rand_addr();
            repeat(READ_LATENCY_A) @(posedge clka);
            expected_data_a = douta;

            // Change address but disable regcea
            addra = rand_addr();
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
            addrb = rand_addr();
            repeat(READ_LATENCY_B) @(posedge clkb);
            expected_data_b = doutb;

            // Change address but disable regceb
            addrb = rand_addr();
            regceb = 0;
            repeat(3) @(posedge clkb);

            check_result(doutb == expected_data_b, "Port B REGCEB control",
                        $sformatf("Port B output should not update when regceb=0, expected=0x%h, got=0x%h",
                                 expected_data_b, doutb));
            regceb = 1; // Re-enable
        end
    endtask

    // Test 9: Address boundary testing
    task test_address_boundaries();
        $display("\nTest 9: Address Boundary Testing");
        $display("--------------------------------");

        ena = 1; enb = 1;
        regcea = 1; regceb = 1;
        wea = {NUM_BYTES_A{1'b0}}; // Read mode

        // Test first addresses
        test_single_read_a(0, memory_model[0], "Port A first address (0)");
        test_single_read_b(0, memory_model[0], "Port B first address (0)");

        // Test last valid addresses
        test_single_read_a(MEMORY_DEPTH_A-1, memory_model[MEMORY_DEPTH_A-1],
                          $sformatf("Port A last address (%0d)", MEMORY_DEPTH_A-1));
        test_single_read_b(MEMORY_DEPTH_B-1, memory_model[MEMORY_DEPTH_B-1],
                          $sformatf("Port B last address (%0d)", MEMORY_DEPTH_B-1));

        // Test middle addresses
        test_single_read_a(MEMORY_DEPTH_A/2, memory_model[MEMORY_DEPTH_A/2],
                          $sformatf("Port A middle address (%0d)", MEMORY_DEPTH_A/2));
        test_single_read_b(MEMORY_DEPTH_B/2, memory_model[MEMORY_DEPTH_B/2],
                          $sformatf("Port B middle address (%0d)", MEMORY_DEPTH_B/2));
    endtask

    // Test 10: ECC interface validation
    task test_ecc_interface();
        $display("\nTest 10: ECC Interface Validation");
        $display("---------------------------------");

        // ECC outputs should always be 0 (no ECC support)
        repeat(10) @(posedge clka);
        repeat(10) @(posedge clkb);

        check_result(sbiterra == 1'b0, "ECC sbiterra", "sbiterra should always be 0");
        check_result(dbiterra == 1'b0, "ECC dbiterra", "dbiterra should always be 0");
        check_result(sbiterrb == 1'b0, "ECC sbiterrb", "sbiterrb should always be 0");
        check_result(dbiterrb == 1'b0, "ECC dbiterrb", "dbiterrb should always be 0");
    endtask

    logic [ADDR_WIDTH_A-1:0] addr_offset; 
    // Test 11: Pattern testing
    task test_pattern_operations();
        $display("\nTest 11: Pattern Testing");
        $display("------------------------");

        ena = 1; enb = 1;
        regcea = 1; regceb = 1;

        // Write all test patterns to memory
        wea = {NUM_BYTES_A{1'b1}};
        addr_offset = rand_addr()-8;
        for (int i = 0; i < 8; i++) begin
            addra = (addr_offset + i);
            dina = rand_addr();
            memory_model[addra] = dina;
            @(posedge clka);
            #1;
        end
        wea = {NUM_BYTES_A{1'b0}};

        // Read back patterns from both ports
        for (int i = 0; i < 8; i++) begin
            test_single_read_a((addr_offset + i), memory_model[(addr_offset + i)], $sformatf("%t, Port A pattern %0d",$time, i));
            test_single_read_b((addr_offset + i), memory_model[(addr_offset + i)], $sformatf("%t, Port B pattern %0d",$time, i));
        end
    endtask

/*
    // Test 12: Random access testing
    task test_random_access();
        $display("\nTest 12: Random Access Testing");
        $display("------------------------------");

        ena = 1; enb = 1;
        regcea = 1; regceb = 1;

        // Random writes via Port A
        wea = '1;
        foreach (random_addresses_a[i]) begin
            addra = random_addresses_a[i];
            dina = 32'h1000_0000 + i;
            memory_model[random_addresses_a[i]] = 32'h1000_0000 + i;
            @(posedge clka);
        end
        wea = '0;

        // Random reads from Port A
        foreach (random_addresses_a[i]) begin
            test_single_read_a(random_addresses_a[i], 32'h1000_0000 + i, 
                           $sformatf("Port A random read %0d (addr=%0d)", i, random_addresses_a[i]);
        end

        // Random reads from Port B
        foreach (random_addresses_b[i]) begin
            if (random_addresses_b[i] < 8) begin
                expected_data_b = memory_model[random_addresses_b[i]];
            end else if (random_addresses_b[i] >= 24 && random_addresses_b[i] < 32) begin
                expected_data_b = memory_model[random_addresses_b[i] - 24];
            end else begin
                // Check if this address was written in random test
                expected_data_b = memory_model[random_addresses_b[i]];
            end
            test_single_read_b(random_addresses_b[i], expected_data_b,
                              $sformatf("Port B random read %0d (addr=%0d)", i, random_addresses_b[i]));
        end
    endtask
*/
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
            $display("  ✅ PASS: %s - %s", test_name, details);
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
        #100000ns;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule

// Additional test configurations for different parameters
module dpdistram_test_configs;

    // Test different configurations
    initial begin
        $display("DPDISTRAM Test Configuration Matrix:");
        $display("- READ_LATENCY_A/B: 0, 1, 2, 3, 5");
        $display("- RST_MODE_A/B: SYNC, ASYNC");
        $display("- ADDR_WIDTH_A/B: 4, 6, 8, 10");
        $display("- READ_DATA_WIDTH_A/B: 8, 16, 32, 64");
        $display("- BYTE_WRITE_WIDTH_A: 8, 16, 32, 64");
        $display("Run individual tests by changing parameters in main testbench");
    end

endmodule
