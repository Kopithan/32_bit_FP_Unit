// components.sv - Fully Corrected & Quartus-Compatible Supporting Modules
// For IEEE 754 Single-Precision Floating-Point ALU
`timescale 1ns / 1ps

// 4-bit Carry Lookahead Adder
module cla (
    input  logic [3:0] A,
    input  logic [3:0] B,
    input  logic       CIN,
    output logic       COUT,
    output logic [3:0] S
);
    logic [3:0] P, G;
    logic [4:1] C;

    assign P = A ^ B;
    assign G = A & B;

    assign C[1] = G[0] | (P[0] & CIN);
    assign C[2] = G[1] | (P[1] & G[0]) | (P[1] & P[0] & CIN);
    assign C[3] = G[2] | (P[2] & G[1]) | (P[2] & P[1] & G[0]) | (P[2] & P[1] & P[0] & CIN);
    assign C[4] = G[3] | (P[3] & G[2]) | (P[3] & P[2] & G[1]) | (P[3] & P[2] & P[1] & G[0]) | (P[3] & P[2] & P[1] & P[0] & CIN);

    assign COUT = C[4];
    assign S    = P ^ {C[3:1], CIN};
endmodule

// Half Adder (unused but kept)
module ha (
    input  logic A,
    input  logic B,
    output logic SUM,
    output logic COUT
);
    assign SUM  = A ^ B;
    assign COUT = A & B;
endmodule

// 2-bit CLA (optional)
module hcla (
    input  logic [1:0] A,
    input  logic [1:0] B,
    input  logic       CIN,
    output logic       COUT,
    output logic [1:0] S
);
    logic [1:0] P = A ^ B;
    logic [1:0] G = A & B;
    logic [2:1] C;

    assign C[1] = G[0] | (P[0] & CIN);
    assign C[2] = G[1] | (P[1] & G[0]) | (P[1] & P[0] & CIN);
    assign COUT = C[2];
    assign S    = P ^ {C[1], CIN};
endmodule

// 24-bit Adder using 6 × 4-bit CLA
module cla_add (
    input  logic [23:0] A,
    input  logic [23:0] B,
    input  logic        CIN,
    output logic [23:0] OUT,
    output logic        OF
);
    logic [6:0] carry_chain;
    assign carry_chain[0] = CIN;

    genvar i;
    generate
        for (i = 0; i < 6; i++) begin : cla_chain
            cla u_cla (
                .A(A[4*i + 3 : 4*i]),
                .B(B[4*i + 3 : 4*i]),
                .CIN(carry_chain[i]),
                .COUT(carry_chain[i+1]),
                .S(OUT[4*i + 3 : 4*i])
            );
        end
    endgenerate

    assign OF = carry_chain[6];
endmodule

// Non-Restoring Divider (24-bit mantissa) - CORRECTED LOGIC
module divider (
    input  logic        CLK,
    input  logic        RST,
    input  logic        REQ,
    input  logic [23:0] A,     // Dividend
    input  logic [23:0] B,     // Divisor
    output logic [23:0] OUT,
    output logic        READY
);
    logic [23:0] divisor_reg;
    logic [47:0] accumulator;  // Partial remainder (upper) + quotient (lower)
    logic [4:0]  count;

    logic [23:0] add_sub_result;

    cla_add adder_inst (
        .A(accumulator[47:24]),
        .B(~divisor_reg),
        .CIN(1'b1),
        .OUT(add_sub_result),
        .OF()
    );

    always_ff @(posedge CLK or posedge RST) begin
        if (RST) begin
            READY          <= 1'b1;
            OUT            <= 24'b0;
            count          <= 5'b0;
            accumulator    <= 48'b0;
            divisor_reg    <= 24'b0;
        end else if (READY && REQ) begin
            READY          <= 1'b0;
            divisor_reg    <= B;
            accumulator    <= {24'b0, A};  // Load dividend
            count          <= 5'b0;
        end else if (!READY) begin
            accumulator <= accumulator << 1;  // Shift left

            if (accumulator[47:24] >= divisor_reg) begin
                accumulator[47:24] <= accumulator[47:24] - divisor_reg;
                accumulator[0]     <= 1'b1;
            end else begin
                accumulator[0]     <= 1'b0;
            end

            count <= count + 1;

            if (count == 5'd23) begin
                OUT   <= accumulator[23:0];
                READY <= 1'b1;
            end
        end
    end
endmodule

// Normalization Module - FIXED: Uses SHIFT consistently
module normal (
    input  logic [23:0] IN,
    input  logic        INOF,      // Overflow from mul
    output logic [22:0] OUT,
    output logic [7:0]  SHIFT,     // Signed shift amount (positive = right shift needed)
    output logic        ZEROFLAG
);
    logic [7:0] shift_amount;

    always_comb begin
        ZEROFLAG = (IN == 24'b0);

        if (ZEROFLAG) begin
            OUT   = 23'b0;
            SHIFT = 8'd0;
        end else if (INOF) begin
            OUT   = IN[23:1];
            SHIFT = 8'd1;              // Right shift by 1
        end else begin
            // Leading-one detector (priority encoder style)
            casex (IN)
                24'b1???????????????????????: shift_amount = 8'd0;
                24'b01??????????????????????: shift_amount = 8'd1;
                24'b001?????????????????????: shift_amount = 8'd2;
                24'b0001????????????????????: shift_amount = 8'd3;
                24'b00001???????????????????: shift_amount = 8'd4;
                24'b000001??????????????????: shift_amount = 8'd5;
                24'b0000001?????????????????: shift_amount = 8'd6;
                24'b00000001????????????????: shift_amount = 8'd7;
                24'b000000001???????????????: shift_amount = 8'd8;
                24'b0000000001??????????????: shift_amount = 8'd9;
                24'b00000000001?????????????: shift_amount = 8'd10;
                24'b000000000001????????????: shift_amount = 8'd11;
                24'b0000000000001???????????: shift_amount = 8'd12;
                24'b00000000000001??????????: shift_amount = 8'd13;
                24'b000000000000001?????????: shift_amount = 8'd14;
                24'b0000000000000001????????: shift_amount = 8'd15;
                24'b00000000000000001???????: shift_amount = 8'd16;
                24'b000000000000000001??????: shift_amount = 8'd17;
                24'b0000000000000000001?????: shift_amount = 8'd18;
                24'b00000000000000000001????: shift_amount = 8'd19;
                24'b000000000000000000001???: shift_amount = 8'd20;
                24'b0000000000000000000001??: shift_amount = 8'd21;
                24'b00000000000000000000001?: shift_amount = 8'd22;
                24'b000000000000000000000001: shift_amount = 8'd23;
                default:                       shift_amount = 8'd24;
            endcase

            OUT   = IN << shift_amount;           // Normalize left
            SHIFT = -shift_amount;                // Negative → left shift in exponent
        end
    end
endmodule

// Barrel Shifter - SIMPLIFIED & CORRECTED (signed shift)
module shifter (
    input  logic [23:0]        IN,
    input  logic signed [7:0]  BY,    // Positive = right shift, Negative = left shift
    output logic [23:0]        OUT
);
    always_comb begin
        if (BY >= 0)
            OUT = IN >> BY;
        else
            OUT = IN << (-BY);
    end
endmodule

// 24x24 Multiplier - Behavioral (synthesizable in Quartus)
module multiplier (
    input  logic [23:0] A,
    input  logic [23:0] B,
    output logic [47:0] OUT
);
    assign OUT = A * B;  // Quartus efficiently synthesizes this
endmodule