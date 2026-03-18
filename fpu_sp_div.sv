module fpu_sp_div (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [31:0]  din1,
    input  logic [31:0]  din2,
    input  logic         dval,
    output logic [31:0]  result,
    output logic         rdy
);

    typedef enum logic [3:0] {
        WAIT_REQ      = 4'd0,
        UNPACK        = 4'd1,
        SPECIAL_CASES = 4'd2,
        NORMALISE_A   = 4'd3,
        NORMALISE_B   = 4'd4,
        DIVIDE_0      = 4'd5,
        DIVIDE_1      = 4'd6,
        DIVIDE_2      = 4'd7,
        DIVIDE_3      = 4'd8,
        NORMALISE_1   = 4'd9,
        NORMALISE_2   = 4'd10,
        ROUND         = 4'd11,
        PACK          = 4'd12,
        OUT_RDY       = 4'd13
    } state_t;

    state_t      state;

    logic [31:0] a, b, z;
    logic [23:0] a_m, b_m, z_m;
    logic [9:0]  a_e, b_e, z_e;
    logic        a_s, b_s, z_s;
    logic        guard, round_bit, sticky;
    logic [50:0] quotient, divisor, dividend, remainder;
    logic [5:0]  count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= WAIT_REQ;
            rdy    <= 1'b0;
            result <= 32'b0;
            a <= 32'b0;
            b <= 32'b0;
            z <= 32'b0;
            a_m <= 24'b0;
            b_m <= 24'b0;
            z_m <= 24'b0;
            a_e <= 10'b0;
            b_e <= 10'b0;
            z_e <= 10'b0;
            a_s <= 1'b0;
            b_s <= 1'b0;
            z_s <= 1'b0;
            guard <= 1'b0;
            round_bit <= 1'b0;
            sticky <= 1'b0;
            quotient <= 51'b0;
            divisor <= 51'b0;
            dividend <= 51'b0;
            remainder <= 51'b0;
            count <= 6'b0;
        end else begin
            case (state)
                WAIT_REQ: begin
                    rdy <= 1'b0;
                    if (dval) begin
                        a <= din1;
                        b <= din2;
                        state <= UNPACK;
                    end
                end
                UNPACK: begin
                    a_m <= a[22:0];
                    b_m <= b[22:0];
                    a_e <= a[30:23] - 127;
                    b_e <= b[30:23] - 127;
                    a_s <= a[31];
                    b_s <= b[31];
                    state <= SPECIAL_CASES;
                end
                SPECIAL_CASES: begin
                    // NaN input
                    if ((a_e == 128 && a_m != 0) || (b_e == 128 && b_m != 0)) begin
                        z[31]    <= 1'b0;
                        z[30:23] <= 8'd255;
                        z[22]    <= 1'b1;
                        z[21:0]  <= 22'd0;
                        state    <= OUT_RDY;
                    // Inf / Inf = NaN
                    end else if ((a_e == 128) && (b_e == 128)) begin
                        z[31]    <= 1'b0;
                        z[30:23] <= 8'd255;
                        z[22]    <= 1'b1;
                        z[21:0]  <= 22'd0;
                        state    <= OUT_RDY;
                    // a is infinity
                    end else if (a_e == 128) begin
                        z[31]    <= a_s ^ b_s;
                        z[30:23] <= 8'd255;
                        z[22:0]  <= 23'd0;
                        state    <= OUT_RDY;
                    // Divide by zero (b=0 and a!=0)
                    end else if (($signed(b_e) == -127 && b_m == 0) && !($signed(a_e) == -127 && a_m == 0)) begin
                        z[31]    <= a_s ^ b_s;
                        z[30:23] <= 8'd255;
                        z[22:0]  <= 23'd0;
                        state    <= OUT_RDY;
                    // b is infinity
                    end else if (b_e == 128) begin
                        z[31]    <= a_s ^ b_s;
                        z[30:23] <= 8'd0;
                        z[22:0]  <= 23'd0;
                        state    <= OUT_RDY;
                    // a is zero (and b!=0)
                    end else if (($signed(a_e) == -127 && a_m == 0) && !($signed(b_e) == -127 && b_m == 0)) begin
                        z[31]    <= a_s ^ b_s;
                        z[30:23] <= 8'd0;
                        z[22:0]  <= 23'd0;
                        state    <= OUT_RDY;
                    // 0 / 0 = NaN
                    end else if (($signed(a_e) == -127 && a_m == 0) && ($signed(b_e) == -127 && b_m == 0)) begin
                        z[31]    <= 1'b0;
                        z[30:23] <= 8'd255;
                        z[22]    <= 1'b1;
                        z[21:0]  <= 22'd0;
                        state    <= OUT_RDY;
                    end else begin
                        // Denormal handling
                        if ($signed(a_e) == -127) a_e <= -126; else a_m[23] <= 1'b1;
                        if ($signed(b_e) == -127) b_e <= -126; else b_m[23] <= 1'b1;
                        state <= NORMALISE_A;
                    end
                end
                NORMALISE_A: begin
                    if (a_m[23]) state <= NORMALISE_B;
                    else begin
                        a_m <= a_m << 1;
                        a_e <= a_e - 1;
                    end
                end
                NORMALISE_B: begin
                    if (b_m[23]) state <= DIVIDE_0;
                    else begin
                        b_m <= b_m << 1;
                        b_e <= b_e - 1;
                    end
                end
                DIVIDE_0: begin
                    z_s       <= a_s ^ b_s;
                    z_e       <= a_e - b_e;
                    quotient  <= 0;
                    remainder <= 0;
                    count     <= 0;
                    dividend  <= a_m << 27;
                    divisor   <= b_m;
                    state     <= DIVIDE_1;
                end
                DIVIDE_1: begin
                    quotient   <= quotient << 1;
                    remainder  <= remainder << 1;
                    remainder[0] <= dividend[50];
                    dividend   <= dividend << 1;
                    state      <= DIVIDE_2;
                end
                DIVIDE_2: begin
                    if (remainder >= divisor) begin
                        quotient[0] <= 1'b1;
                        remainder   <= remainder - divisor;
                    end
                    if (count == 49) state <= DIVIDE_3;
                    else begin
                        count <= count + 1;
                        state <= DIVIDE_1;
                    end
                end
                DIVIDE_3: begin
                    z_m       <= quotient[26:3];
                    guard     <= quotient[2];
                    round_bit <= quotient[1];
                    sticky    <= quotient[0] | (remainder != 0);
                    state     <= NORMALISE_1;
                end
                NORMALISE_1: begin
                    if (z_m[23] == 0 && $signed(z_e) > -126) begin
                        z_e    <= z_e - 1;
                        z_m    <= z_m << 1;
                        z_m[0] <= guard;
                        guard  <= round_bit;
                        round_bit <= 0;
                    end else state <= NORMALISE_2;
                end
                NORMALISE_2: begin
                    if ($signed(z_e) < -126) begin
                        z_e    <= z_e + 1;
                        z_m    <= z_m >> 1;
                        guard  <= z_m[0];
                        round_bit <= guard;
                        sticky <= sticky | round_bit;
                    end else state <= ROUND;
                end
                ROUND: begin
                    if (guard && (round_bit | sticky | z_m[0])) begin
                        z_m <= z_m + 1;
                        if (z_m == 24'hffffff) z_e <= z_e + 1;
                    end
                    state <= PACK;
                end
                PACK: begin
                    z[22:0]  <= z_m[22:0];
                    z[30:23] <= z_e[7:0] + 127;
                    z[31]    <= z_s;
                    if ($signed(z_e) == -126 && z_m[23] == 0) z[30:23] <= 8'd0;
                    if ($signed(z_e) > 127) begin
                        z[22:0]  <= 23'd0;
                        z[30:23] <= 8'd255;
                        z[31]    <= z_s;
                    end
                    state <= OUT_RDY;
                end
                OUT_RDY: begin
                    rdy    <= 1'b1;
                    result <= z;
                    state  <= WAIT_REQ;
                end
                default: state <= WAIT_REQ;
            endcase
        end
    end

endmodule