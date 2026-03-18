// tb_fp_unit_fixed.sv
`timescale 1ns/1ps

module tb_fp_unit_fixed;

    logic        clk = 0;
    logic        rst;
    logic [31:0] a, b;
    logic [1:0]  op;
    logic        valid_in;
    logic [31:0] result;
    logic        valid_out;
    logic        invalid;

    // DUT
    fp_unit dut (
        .clk(clk),
        .rst(rst),
        .a(a),
        .b(b),
        .op_in(op),
        .valid_in(valid_in),
        .result(result),
        .valid_out(valid_out),
        .invalid(invalid)
    );

    // 50 MHz clock
    always #10 clk = ~clk;

    // Task to check result when valid_out goes high
    task automatic check_result(input [31:0] expected);
        begin
            wait(valid_out === 1);
            #10; // small delay for stable result
            $display("%0t | result=%h | expected=%h | %s",
                     $time, result, expected,
                     (result == expected) ? "PASS" : "FAIL");
        end
    endtask

    initial begin
        // Reset
        rst = 1;
        valid_in = 0;
        a = 0; b = 0; op = 0;
        #40 rst = 0;

        $display("\n=== Starting FP Unit Tests ===\n");

        // Test 1: 2.0 + 3.0 = 5.0
        a = 32'h40000000; // 2.0
        b = 32'h40400000; // 3.0
        op = 2'b00;       // add
        valid_in = 1;
        #20 valid_in = 0;
        check_result(32'h40A00000);

        // Test 2: 3.0 - 2.0 = 1.0
        a = 32'h40400000; // 3.0
        b = 32'h40000000; // 2.0
        op = 2'b01;       // sub
        valid_in = 1;
        #20 valid_in = 0;
        check_result(32'h3F800000);

        // Test 3: 2.0 * 4.0 = 8.0
        a = 32'h40000000; // 2.0
        b = 32'h40800000; // 4.0
        op = 2'b10;       // mul
        valid_in = 1;
        #20 valid_in = 0;
        check_result(32'h41000000);

        // Test 4: 6.0 / 2.0 = 3.0
        a = 32'h40C00000; // 6.0
        b = 32'h40000000; // 2.0
        op = 2'b11;       // div
        valid_in = 1;
        #20 valid_in = 0;
        check_result(32'h40400000);

        $display("\n=== All tests completed ===\n");
        $finish;
    end

    // Optional: monitor for debugging
    initial begin
        $monitor("Time=%0t | valid_in=%b | valid_out=%b | result=%h | invalid=%b", 
                 $time, valid_in, valid_out, result, invalid);
    end

endmodule
