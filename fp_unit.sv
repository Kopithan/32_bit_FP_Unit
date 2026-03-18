// fp_unit.sv - Fully Quartus-Compatible 32-bit Floating-Point Unit
// Supports: Add, Sub, Mul, Div (IEEE 754 single-precision)
// Pipelined, uses custom divider, multiplier, normalizer from components.sv
`timescale 1ns / 1ps

module fp_unit (
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [1:0]  op_in,       // 00: add, 01: sub, 10: mul, 11: div
    input  logic        valid_in,
    output logic [31:0] result,
    output logic        valid_out,
    output logic        invalid      // NaN, invalid op, div-by-zero
);

    localparam int BIAS     = 127;
    localparam logic [7:0] EXP_INF = 8'hFF;

    // ====================== Stage 0: Input Registers ======================
    logic [1:0]  op_s0;
    logic        sa_s0, sb_s0;
    logic [7:0]  ea_s0, eb_s0;
    logic [22:0] ma_s0, mb_s0;
    logic        a_zero_s0, b_zero_s0;
    logic        a_inf_s0,  b_inf_s0;
    logic        a_nan_s0,  b_nan_s0;
    logic        valid_s0;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_s0 <= 1'b0;
        end else begin
            valid_s0 <= valid_in;
            if (valid_in) begin
                op_s0 <= op_in;
                sa_s0 <= a[31];
                sb_s0 <= b[31];
                ea_s0 <= a[30:23];
                eb_s0 <= b[30:23];
                ma_s0 <= a[22:0];
                mb_s0 <= b[22:0];

                a_zero_s0 <= (a[30:23] == 0) && (a[22:0] == 0);
                b_zero_s0 <= (b[30:23] == 0) && (b[22:0] == 0);
                a_inf_s0  <= (a[30:23] == EXP_INF) && (a[22:0] == 0);
                b_inf_s0  <= (b[30:23] == EXP_INF) && (b[22:0] == 0);
                a_nan_s0  <= (a[30:23] == EXP_INF) && (a[22:0] != 0);
                b_nan_s0  <= (b[30:23] == EXP_INF) && (b[22:0] != 0);
            end
        end
    end

    // ====================== Stage 1: Hidden Bit & Components ======================
    logic [23:0] mant_a_s1, mant_b_s1;
    logic [1:0]  op_s1;
    logic        valid_s1;
    logic        a_zero_s1, b_zero_s1;
    logic        a_inf_s1,  b_inf_s1;
    logic        a_nan_s1,  b_nan_s1;

    always_ff @(posedge clk) begin
        if (valid_s0) begin
            mant_a_s1 <= {~(a_zero_s0), ma_s0};
            mant_b_s1 <= {~(b_zero_s0), mb_s0};

            op_s1     <= op_s0;
            valid_s1  <= 1'b1;

            a_zero_s1 <= a_zero_s0;
            b_zero_s1 <= b_zero_s0;
            a_inf_s1  <= a_inf_s0;
            b_inf_s1  <= b_inf_s0;
            a_nan_s1  <= a_nan_s0;
            b_nan_s1  <= b_nan_s0;
        end else begin
            valid_s1 <= 1'b0;
        end
    end

    // Multiplier (combinational)
    logic [47:0] mul_result;
    multiplier mul_inst (
        .A(mant_a_s1),
        .B(mant_b_s1),
        .OUT(mul_result)
    );

    // Divider (multi-cycle)
    logic        div_start;
    logic [23:0] div_quotient;
    logic        div_ready;

    assign div_start = valid_s1 && (op_s1 == 2'b11);

    divider div_inst (
        .CLK(clk),
        .RST(rst),
        .REQ(div_start),
        .A(mant_a_s1),
        .B(mant_b_s1),
        .OUT(div_quotient),
        .READY(div_ready)
    );

    // ====================== Stage 2: Exponent Alignment (Add/Sub only) ======================
    logic        effective_sub_s2;
    logic        sign_out_s2;
    logic [7:0]  exp_align_s2;
    logic [23:0] mant_large_s2;
    logic [23:0] mant_small_s2;
    logic [1:0]  op_s2;
    logic        valid_s2;
    logic        early_invalid_s2;

    always_comb begin
        effective_sub_s2 = sa_s0 ^ sb_s0 ^ op_s0[0];

        if (ea_s0 >= eb_s0) begin
            exp_align_s2       = ea_s0;
            sign_out_s2        = sa_s0;
            mant_large_s2      = mant_a_s1;
            mant_small_s2      = mant_b_s1 >> (ea_s0 - eb_s0);
        end else begin
            exp_align_s2       = eb_s0;
            sign_out_s2        = sb_s0 ^ op_s0[0];
            mant_large_s2      = mant_b_s1;
            mant_small_s2      = mant_a_s1 >> (eb_s0 - ea_s0);
        end

        early_invalid_s2 = a_nan_s1 || b_nan_s1 || (op_s0 == 2'b11 && b_zero_s1);
    end

    always_ff @(posedge clk) begin
        if (valid_s1) begin
            op_s2         <= op_s1;
            valid_s2      <= 1'b1;
            early_invalid_s2 <= early_invalid_s2; // propagate
        end else begin
            valid_s2 <= 1'b0;
        end
    end

    // Store aligned values only for add/sub
    logic        sign_s3;
    logic [7:0]  exp_s3;
    logic [24:0] mant_sum_s3;

    always_ff @(posedge clk) begin
        if (valid_s2 && (op_s2 == 2'b00 || op_s2 == 2'b01)) begin
            sign_s3  <= sign_out_s2;
            exp_s3   <= exp_align_s2;
            if (effective_sub_s2)
                mant_sum_s3 <= {1'b0, mant_large_s2} - {1'b0, mant_small_s2};
            else
                mant_sum_s3 <= {1'b0, mant_large_s2} + {1'b0, mant_small_s2};
        end
    end

    // ====================== Stage 3: Operation Selection ======================
    logic [24:0] mant_pre_norm;
    logic [7:0]  exp_pre_norm;
    logic        sign_pre_norm;
    logic        op_is_div;
    logic        valid_s3;

    always_comb begin
        mant_pre_norm = 25'b0;
        exp_pre_norm  = 8'b0;
        sign_pre_norm = 1'b0;
        op_is_div     = (op_s2 == 2'b11);

        case (op_s2)
            2'b00, 2'b01: begin
                mant_pre_norm = mant_sum_s3;
                exp_pre_norm  = exp_s3;
                sign_pre_norm = sign_s3;
            end
            2'b10: begin  // mul
                mant_pre_norm = mul_result[47:23];
                exp_pre_norm  = ea_s0 + eb_s0 - BIAS + mul_result[47];
                sign_pre_norm = sa_s0 ^ sb_s0;
            end
            2'b11: begin  // div
                mant_pre_norm = {div_quotient, 1'b0};
                exp_pre_norm  = ea_s0 - eb_s0 + BIAS;
                sign_pre_norm = sa_s0 ^ sb_s0;
            end
            default: begin
                mant_pre_norm = 0;
                exp_pre_norm  = 0;
                sign_pre_norm = 0;
            end
        endcase
    end

    // ====================== Normalization ======================
    logic [22:0] mant_norm;
    logic [7:0]  shift_amt;
    logic        zero_flag;

    normal norm_inst (
        .IN(mant_pre_norm[23:0]),
        .INOF(mant_pre_norm[24]),
        .OUT(mant_norm),
        .SHIFT(shift_amt),
        .ZEROFLAG(zero_flag)
    );

    // ====================== Stage 4: Final Exponent & Pack ======================
    logic [7:0]  final_exp;
    logic        final_sign;
    logic [22:0] final_mant;
    logic        final_invalid;
    logic        final_valid;

    always_ff @(posedge clk) begin
        final_sign   <= sign_pre_norm;
        final_mant   <= mant_norm;
        final_exp    <= exp_pre_norm + $signed(shift_amt);
        final_invalid <= early_invalid_s2 || (op_is_div && b_zero_s1);
        final_valid  <= valid_s2 && (op_s2 != 2'b11 || div_ready);
    end

    // Delay valid for div to match div_ready
    logic valid_out_reg;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) valid_out_reg <= 0;
        else     valid_out_reg <= final_valid;
    end

    assign valid_out = valid_out_reg;

    // ====================== Output Logic ======================
    always_comb begin
        invalid = final_invalid || a_nan_s0 || b_nan_s0;

        if (invalid || a_nan_s0 || b_nan_s0)
            result = 32'h7FC00000; // Quiet NaN
        else if (a_inf_s0 || b_inf_s0)
            result = {sa_s0 ^ sb_s0 ^ op_s0[0], EXP_INF, 23'b0};
        else if (zero_flag || final_exp <= 0)
            result = {final_sign, 31'b0}; // Zero
        else if (final_exp >= EXP_INF)
            result = {final_sign, EXP_INF, 23'b0}; // Infinity
        else
            result = {final_sign, final_exp, final_mant};
    end

endmodule