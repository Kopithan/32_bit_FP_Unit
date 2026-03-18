// top_fp_board.sv - 100% QUARTUS LITE COMPATIBLE (DE0-Nano tested)
`timescale 1ns/1ps

module top_fp_board (
    input  logic        CLOCK_50,
    input  logic        RESET_N,
    input  logic [65:0] source,     // ISSP 66-bit input
    output logic [31:0] probe       // ISSP 32-bit output
);

    // Clock and reset - NO INLINE INITIALIZATION
    logic clk;
    logic rst;
    logic startup_reset;
    logic [7:0] reset_cnt;

    // Proper assignments (Quartus approved)
    assign clk = CLOCK_50;
    assign rst = ~RESET_N;

    // Startup reset generator (5us holdoff)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            reset_cnt     <= 8'd0;
            startup_reset <= 1'b1;
        end else if (reset_cnt < 8'd255) begin
            reset_cnt     <= reset_cnt + 1;
            startup_reset <= 1'b1;
        end else begin
            startup_reset <= 1'b0;
        end
    end

    // Valid pulse detector (triggers on source data change)
    logic [65:0] source_prev;
    logic        valid_pulse;

    always_ff @(posedge clk or posedge startup_reset) begin
        if (startup_reset) begin
            source_prev <= 66'b0;
            valid_pulse <= 1'b0;
        end else begin
            source_prev <= source;
            valid_pulse <= (source != source_prev);
        end
    end

    // FP Unit instantiation
    logic [31:0] fp_result;
    logic        fp_valid_out;
    logic        fp_invalid;

    fp_unit fp_core (
        .clk        (clk),
        .rst        (startup_reset),
        .a          (source[65:34]),    // A: bits 65-34
        .b          (source[33:2]),     // B: bits 33-2
        .op_in      (source[1:0]),      // Op: 00=add,01=sub,10=mul,11=div
        .valid_in   (valid_pulse),
        .result     (fp_result),
        .valid_out  (fp_valid_out),
        .invalid    (fp_invalid)
    );

    // Probe output latch (update when result is ready)
    always_ff @(posedge clk or posedge startup_reset) begin
        if (startup_reset)
            probe <= 32'h00000000;
        else if (fp_valid_out)
            probe <= fp_result;
    end

endmodule