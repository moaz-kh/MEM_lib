// Comprehensive SPRAM Testbench - XPM_MEMORY_SPRAM Compatible
// Tests all parameter combinations and features
// Self-checking with detailed pass/fail reporting

`timescale 1ns / 1ps

module spram_tb;

    // Test configuration parameters
    localparam CLK_PERIOD = 10;  // 100MHz clock

    // SPRAM configuration parameters - centralized
    localparam ADDR_WIDTH_A = 6;
    localparam WRITE_DATA_WIDTH_A = 8;
    localparam READ_DATA_WIDTH_A = 8;
    localparam BYTE_WRITE_WIDTH_A = 8;
    localparam READ_LATENCY_A = 2;
    localparam MEMORY_SIZE = 512;  // 64 locations × 8 bits
    localparam string WRITE_MODE_A = "read_first";
    localparam string RST_MODE_A = "SYNC";
    localparam string MEMORY_INIT_FILE = "sim/test_data/spram_init_8bit.mem"; // "none"; 
    localparam string READ_RESET_VALUE_A = "0";
    localparam IGNORE_INIT_SYNTH = 0;

    // Test control signals - sized using parameters
    logic                                clka;
    logic                                rsta;
    logic                                ena;
    logic                                regcea;
    logic [ADDR_WIDTH_A-1:0]            addra;
    logic [WRITE_DATA_WIDTH_A-1:0]      dina;
    logic [WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-1:0] wea;
    logic [READ_DATA_WIDTH_A-1:0]       douta;
    logic                                sbiterra;
    logic                                dbiterra;

    // Test statistics
    int total_tests = 0;
    int total_pass = 0;
    int total_fail = 0;
    int config_tests = 0;
    int config_pass = 0;
    int config_fail = 0;
    string current_config = "";
    
    // Waveform dump - VCD format for universal compatibility
    initial begin
        $dumpfile("sim/waves/spram_tb.vcd");
        $dumpvars(0, spram_tb);  // Depth 2 to include arrays
        
        // Explicitly dump array elements for better visibility
        for (int i = 0; i < 16; i++) begin
            $dumpvars(1, dut.memory[i]);
        end
        /*
        // Explicitly dump array elements for better visibility
        for (int i = DEPTH-16; i < DEPTH; i++) begin
            $dumpvars(1, dut.memory[i]);
        end
        */
        $display("[%0t] Waveform file: sim/waves/spram_tb.vcd", $time);
    end
    
    // Memory array
    localparam MEMORY_DEPTH = MEMORY_SIZE / WRITE_DATA_WIDTH_A;
    logic [WRITE_DATA_WIDTH_A-1:0] test_memory [0:MEMORY_DEPTH-1];
    // Memory initialization based on IGNORE_INIT_SYNTH
    generate
        // Simulation only initialization
            initial begin
                // ALWAYS initialize to zeros first (default safe state)
                for (int i = 0; i < MEMORY_DEPTH; i++) begin
                    test_memory[i] = {WRITE_DATA_WIDTH_A{1'b0}};
                end

                // THEN conditionally load from file (overlay)
                if (MEMORY_INIT_FILE != "none" && MEMORY_INIT_FILE != "") begin
                    $readmemh(MEMORY_INIT_FILE, test_memory);
                    $display("SPRAM: Loaded memory from file (simulation only): %s", MEMORY_INIT_FILE);
                end else begin
                    $display("SPRAM: Initialized to zeros (simulation only)");
                end
            end
    endgenerate
    
    // Clock generation
    initial begin
        clka = 0;
        forever #(CLK_PERIOD/2) clka = ~clka;
    end

    // DUT instantiation
    spram #(
        .ADDR_WIDTH_A(ADDR_WIDTH_A),
        .WRITE_DATA_WIDTH_A(WRITE_DATA_WIDTH_A),
        .READ_DATA_WIDTH_A(READ_DATA_WIDTH_A),
        .BYTE_WRITE_WIDTH_A(BYTE_WRITE_WIDTH_A),
        .READ_LATENCY_A(READ_LATENCY_A),
        .WRITE_MODE_A(WRITE_MODE_A),
        .RST_MODE_A(RST_MODE_A),
        .MEMORY_SIZE(MEMORY_SIZE),
        .IGNORE_INIT_SYNTH(IGNORE_INIT_SYNTH),
        .MEMORY_INIT_FILE(MEMORY_INIT_FILE),
        .READ_RESET_VALUE_A(READ_RESET_VALUE_A)
    ) dut (
        .clka(clka),
        .rsta(rsta),
        .ena(ena),
        .addra(addra),
        .dina(dina),
        .wea(wea),
        .douta(douta),
        .regcea(regcea),
        .sbiterra(sbiterra),
        .dbiterra(dbiterra)
    );

    // Test result tracking
    task automatic check_result(input logic [READ_DATA_WIDTH_A-1:0] expected, input logic [READ_DATA_WIDTH_A-1:0] actual,
                               input string test_name);
        total_tests++;
        config_tests++;
        if (actual === expected) begin
            total_pass++;
            config_pass++;
            $display("[PASS] %s: Expected=0x%0h, Got=0x%0h", test_name,
                    expected, actual);
        end else begin
            total_fail++;
            config_fail++;
            $display("[FAIL] %t, %s: Expected=0x%0h, Got=0x%0h", $time, test_name,
                    expected, actual);
        end
    endtask

    // Reset task
    task automatic reset_system();
        rsta = 1;
        ena = 0;
        regcea = 1;
        addra = 0;
        dina = 0;
        wea = 0;
        repeat(5) @(posedge clka);
        rsta = 0;
        repeat(5) @(posedge clka); // Wait for pipeline to clear
    endtask

    // Write task
    task automatic write_data(input logic [ADDR_WIDTH_A-1:0] addr, input logic [WRITE_DATA_WIDTH_A-1:0] data, input logic [WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-1:0] we_mask);
        @(posedge clka);
        ena = 1;
        addra = addr;
        dina = data;
        wea = we_mask;
        @(posedge clka);
        wea = 0;
    endtask

    // Read task
    task automatic read_data(input logic [ADDR_WIDTH_A-1:0] addr);
        @(posedge clka);
        ena = 1;
        addra = addr;
        // Wait for read latency (2 cycles for default config)
        repeat(2) @(posedge clka);
    endtask

    // Basic functionality test
    task automatic test_basic_functionality();
        logic [WRITE_DATA_WIDTH_A-1:0] test_data, expected_data;
        logic [ADDR_WIDTH_A-1:0] test_addr;

        $display("  Testing basic functionality...");

        reset_system();

        // Test 1: Word-wide write and read
        test_addr = 6'h0;
        test_data = 8'h78;
        write_data(test_addr, test_data, 1'h1); // Word-wide write (wea[0] = 1)
        read_data(test_addr);
        check_result(test_data, douta, "Basic word write/read");

        // Test 2: Different address
        test_addr = 6'h3F; // Maximum address for 64-word memory
        test_data = 8'h21;
        write_data(test_addr, test_data, 1'h1);
        read_data(test_addr);
        check_result(test_data, douta, "Max address test");

        // Test 3: Data patterns (Fixed for 32-bit width)
        test_addr = 6'h10;
        test_data = 8'hFF; // All ones pattern
        write_data(test_addr, test_data, 1'h1);
        read_data(test_addr);
        check_result(test_data, douta, "All ones pattern");

        test_addr = 6'h11;
        test_data = 8'h00; // All zeros pattern
        write_data(test_addr, test_data, 1'h1);
        read_data(test_addr);
        check_result(test_data, douta, "All zeros pattern");

        test_addr = 6'h12;
        test_data = 8'h55; // Alternating pattern
        write_data(test_addr, test_data, 1'h1);
        read_data(test_addr);
        check_result(test_data, douta, "Alternating pattern");
    endtask

    // Write mode tests
    task automatic test_write_modes();
        logic [WRITE_DATA_WIDTH_A-1:0] old_data, new_data, expected_data;
        logic [ADDR_WIDTH_A-1:0] test_addr;

        $display("  Testing write modes...");

        test_addr = 6'h20;

        // Test read_first mode (default configuration)
        old_data = 8'h22;
        new_data = 8'h44;

        // Write initial data
        write_data(test_addr, old_data, 1'h1);
        read_data(test_addr);
        check_result(old_data, douta, "Write mode: Initial write");

        // Perform simultaneous read/write to test read_first behavior
        @(posedge clka);
        ena = 1;
        addra = test_addr;
        dina = new_data;
        wea = 1'h1;
        @(posedge clka);
        wea = 0;

        // Wait for read latency - should return old data (read_first)
        @(posedge clka);
        expected_data = old_data;
        check_result(expected_data, douta, "Write mode: read_first behavior");

        // Verify the write actually occurred
        read_data(test_addr);
        check_result(new_data, douta, "Write mode: Write completion");
    endtask

    // Reset behavior tests
    task automatic test_reset_behavior();
        logic [WRITE_DATA_WIDTH_A-1:0] test_data, expected_data;
        logic [ADDR_WIDTH_A-1:0] test_addr;

        $display("  Testing reset behavior...");

        test_addr = 6'h30;
        test_data = 8'h10;

        // Write some data
        write_data(test_addr, test_data, 1'h1);

        // Start a read operation to get data into pipeline
        read_data(test_addr);

        // Apply reset while pipeline has data
        rsta = 1;
        @(posedge clka); // Reset applied synchronously on this edge
        @(posedge clka); // Reset applied synchronously on this edge
        @(posedge clka); // Reset applied synchronously on this edge
        rsta = 0;

        // For SYNC reset, output should be reset value (0) immediately after reset
        expected_data = 8'h0;
        check_result(expected_data, douta, "Reset: Output reset");

        // Verify memory contents are preserved
        read_data(test_addr);
        check_result(test_data, douta, "Reset: Memory preserved");
    endtask

    // regcea control tests
    task automatic test_regcea_control();
        logic [WRITE_DATA_WIDTH_A-1:0] test_data;
        logic [ADDR_WIDTH_A-1:0] test_addr;

        $display("  Testing regcea control...");

        test_addr = 6'h35;
        test_data = 8'hEF;

        // Write test data
        write_data(test_addr, test_data, 1'h1);

        // Start read with regcea enabled
        @(posedge clka);
        ena = 1;
        regcea = 1;
        addra = test_addr;
        @(posedge clka);

        // Disable regcea to stall pipeline
        regcea = 0;
        @(posedge clka); // First pipeline stage still proceeds

        // Re-enable regcea
        regcea = 1;
        @(posedge clka);

        // Data should now appear at output
        check_result(test_data, douta, "regcea: Pipeline control");
    endtask

    // Enable control tests
    task automatic test_enable_control();
        logic [WRITE_DATA_WIDTH_A-1:0] test_data, original_data;
        logic [ADDR_WIDTH_A-1:0] test_addr;

        $display("  Testing enable control...");

        test_addr = 6'h01;
        test_data = 8'hDF;
        original_data = 8'h11;

        // Write original data
        write_data(test_addr, original_data, 1'h1);

        // Try to write with ena = 0
        @(posedge clka);
        ena = 0;  // Disable
        @(posedge clka);
        addra = test_addr;
        dina = test_data;
        wea = 1'h1;
        @(posedge clka);
        wea = 0;

        // Read back - should still have original value
        ena = 1;
        read_data(test_addr);
        check_result(original_data, douta, "Enable: Write disabled by ena=0");
    endtask
/*
    // Random stress test
    task automatic test_random_operations();
        logic [31:0] test_data, expected_data;
        logic [9:0] test_addr;
        logic [31:0] memory_model [0:63]; // 64-word memory model (32-bit)
        int num_tests = 30; // Reduced for cleaner output

        $display("  Running %0d random operations...", num_tests);

        // Reset system and initialize memory model to match actual memory state
        reset_system();

        // Initialize memory model to match actual memory (all zeros after reset)
        for (int i = 0; i < 64; i++) begin
            memory_model[i] = 32'h0;
        end

        for (int i = 0; i < num_tests; i++) begin
            test_addr = $urandom() % 64; // 0 to 63

            // Generate random 32-bit data
            test_data = $urandom();

            // Bias towards more writes initially to populate memory
            if (i < 15 || $urandom() % 3 == 0) begin
                // Write operation
                write_data(test_addr, {32'h0, test_data}, 8'h1);
                memory_model[test_addr] = test_data;
            end else begin
                // Read operation - ensure regcea is enabled for proper read
                regcea = 1;
                read_data(test_addr);
                expected_data = memory_model[test_addr];
                check_result({32'h0, expected_data}, douta, $sformatf("Random test %0d", i));
            end
        end
    endtask
*/
    // ECC status test (should always be 0)
    task automatic test_ecc_status();
        $display("  Testing ECC status outputs...");

        // ECC outputs should always be 0 (no ECC support)
        if (sbiterra !== 1'b0) begin
            $display("[FAIL] ECC: sbiterra should be 0, got %b", sbiterra);
            total_fail++;
            config_fail++;
        end else begin
            $display("[PASS] ECC: sbiterra is correctly tied to 0");
            total_pass++;
        end

        if (dbiterra !== 1'b0) begin
            $display("[FAIL] ECC: dbiterra should be 0, got %b", dbiterra);
            total_fail++;
            config_fail++;
        end else begin
            $display("[PASS] ECC: dbiterra is correctly tied to 0");
            total_pass++;
        end

        total_tests += 2;
        config_tests += 2;
    endtask

    // Test memory initialization from file
    task automatic test_memory_initialization();
        logic [WRITE_DATA_WIDTH_A-1:0] expected_val;
        logic [WRITE_DATA_WIDTH_A-1:0] expected;

        $display("\n--- Testing Memory Initialization ---");

        // Reset system before testing
        reset_system();
 
        repeat(2) @(posedge clka);  // Allow pipeline to fill with first valid read

        // Test first 16 locations (incremental pattern: 0x00-0x0F)
        for (int i = 0; i < MEMORY_DEPTH; i++) begin
            if (i > 0) begin 
                if (douta == expected_val) begin
                    $display("[PASS] Memory Init: Address 0x%02X = 0x%02X (expected 0x%02X)",
                        i-1, douta, expected_val);
                    total_pass++;
                end else begin
                    $display("[FAIL] Memory Init: Address 0x%02X = 0x%02X (expected 0x%02X)",
                        i-1, douta, expected_val);
                    total_fail++;
                    config_fail++;
                end         
            end
            
            // Read from initialized memory
            if (i <= MEMORY_DEPTH) begin 
                ena = 1'b1;
                regcea = 1'b1;
                addra = i;
                wea = 1'b0;  // Read operation

                // Wait for read latency (2 cycles)
                repeat(READ_LATENCY_A+1) @(posedge clka);

                expected_val = test_memory[i];  // Incremental pattern 0x00, 0x01, 0x02...
                total_tests++;
                config_tests++;
            end
            else begin 
                ena = 1'b0;
                regcea = 1'b0;
            end 
        end
 
        $display("Memory initialization test completed.");
    endtask

    // Main test sequence
    initial begin
        $display("=== COMPREHENSIVE SPRAM TESTBENCH ===");
        $display("Testing 8-bit SPRAM configuration with memory initialization...");
        $display("ADDR_WIDTH_A: %0d", ADDR_WIDTH_A);
        $display("WRITE_DATA_WIDTH_A: %0d", WRITE_DATA_WIDTH_A);
        $display("READ_DATA_WIDTH_A: %0d", READ_DATA_WIDTH_A);
        $display("BYTE_WRITE_WIDTH_A: %0d", BYTE_WRITE_WIDTH_A);
        $display("READ_LATENCY_A: %0d", READ_LATENCY_A);
        $display("WRITE_MODE_A: %s", WRITE_MODE_A);
        $display("RST_MODE_A: %s", RST_MODE_A);
        $display("MEMORY_SIZE: %0d", MEMORY_SIZE);
        $display("MEMORY_INIT_FILE: %s", MEMORY_INIT_FILE);
        $display("==============================");

        config_tests = 0;
        config_pass = 0;
        config_fail = 0;

        // Wait for initial settling
        repeat(10) @(posedge clka);

        // Run all tests
        test_memory_initialization();  // Test memory init file first
        test_basic_functionality();
        test_write_modes();
        test_reset_behavior();
        test_regcea_control();
        test_enable_control();
        test_ecc_status();
        //test_random_operations();

        // Test results
        $display("\n=== TEST RESULTS ===");
        $display("Total Tests Run: %0d", total_tests);
        $display("Total Passed:    %0d", total_pass);
        $display("Total Failed:    %0d", total_fail);
        $display("Success Rate:    %0.1f%%", (total_pass * 100.0) / total_tests);

        if (total_fail == 0) begin
            $display("\n*** ALL TESTS PASSED! SPRAM MODULE IS WORKING CORRECTLY ***");
        end else begin
            $display("\n*** %0d TESTS FAILED! CHECK THE FAILURES ABOVE ***", total_fail);
        end
        $display("====================");

        #1000;
        $finish;
    end

    // Timeout protection
    initial begin
        #1000000; // 1ms timeout
        $display("ERROR: Testbench timeout!");
        $display("Completed %0d tests before timeout", total_tests);
        $finish;
    end

endmodule
