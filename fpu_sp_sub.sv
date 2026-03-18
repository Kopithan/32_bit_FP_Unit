module fpu_sp_sub (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [31:0]  din1,
    input  logic [31:0]  din2,
    input  logic         dval,
    output logic [31:0]  result,
    output logic         rdy
);

    typedef enum logic [3:0] {
        WAIT_REQ = 4'd0, UNPACK = 4'd1, SPECIAL_CASES = 4'd2, ALIGN = 4'd3,
        ADD_0 = 4'd4, ADD_1 = 4'd5, NORMALISE_1 = 4'd6, NORMALISE_2 = 4'd7,
        ROUND = 4'd8, PACK = 4'd9, OUT_RDY = 4'd10
    } state_t;

    state_t      state;

    logic [31:0] a, b, z;
    logic [26:0] a_m, b_m;
    logic [23:0] z_m;
    logic [9:0]  a_e, b_e, z_e;
    logic        a_s, b_s, z_s;
    logic        guard, round_bit, sticky;
    logic [27:0] pre_sum;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= WAIT_REQ;
            rdy    <= 1'b0;
            result <= 32'b0;
            a <= 32'b0;
            b <= 32'b0;
            z <= 32'b0;
            a_m <= 27'b0;
            b_m <= 27'b0;
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
            pre_sum <= 28'b0;
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
                    a_m <= {a[22:0], 3'b0};
                    b_m <= {b[22:0], 3'b0};
                    a_e <= a[30:23] - 127;
                    b_e <= b[30:23] - 127;
                    a_s <= a[31];
                    b_s <= ~b[31];  
                    state <= SPECIAL_CASES;
                end
                SPECIAL_CASES: begin
                    // NaN check
                    if ((a_e == 128 && a_m != 0) || (b_e == 128 && b_m != 0)) begin
                        z[31] <= 1'b0;
                        z[30:23] <= 255;
                        z[22] <= 1'b1;
                        z[21:0] <= 0;
                        state <= OUT_RDY;
                    // a is infinity
                    end else if (a_e == 128) begin
                        z[31] <= a_s;
                        z[30:23] <= 255;
                        z[22:0] <= 0;
                        // Inf - Inf = NaN
                        if (b_e == 128 && (a_s != b_s)) begin
                            z[31] <= 1'b0;
                            z[30:23] <= 255;
                            z[22] <= 1'b1;
                            z[21:0] <= 0;
                        end
                        state <= OUT_RDY;
                    // b is infinity
                    end else if (b_e == 128) begin
                        z[31] <= b_s;
                        z[30:23] <= 255;
                        z[22:0] <= 0;
                        state <= OUT_RDY;
                    // Both are zero
                    end else if (($signed(a_e) == -127 && a_m == 0) && ($signed(b_e) == -127 && b_m == 0)) begin
                        z[31] <= a_s & b_s;
                        z[30:23] <= 0;
                        z[22:0] <= 0;
                        state <= OUT_RDY;
                    // a is zero
                    end else if (($signed(a_e) == -127) && (a_m == 0)) begin
                        z <= {b_s, b[30:0]};
                        state <= OUT_RDY;
                    // b is zero
                    end else if (($signed(b_e) == -127) && (b_m == 0)) begin
                        z <= din1;
                        state <= OUT_RDY;
                    end else begin
                        // Denormal handling
                        if ($signed(a_e) == -127) a_e <= -126; else a_m[26] <= 1'b1;
                        if ($signed(b_e) == -127) b_e <= -126; else b_m[26] <= 1'b1;
                        state <= ALIGN;
                    end
                end
                ALIGN: begin
                    if ($signed(a_e) > $signed(b_e)) begin
                        b_e   <= b_e + 1;
                        b_m   <= {1'b0, b_m[26:1]};
                        b_m[0] <= b_m[0] | b_m[1];
                    end else if ($signed(a_e) < $signed(b_e)) begin
                        a_e   <= a_e + 1;
                        a_m   <= {1'b0, a_m[26:1]};
                        a_m[0] <= a_m[0] | a_m[1];
                    end else begin
                        state <= ADD_0;
                    end
                end
                ADD_0: begin
                    z_e <= a_e;
                    if (a_s == b_s) begin
                        pre_sum <= a_m + b_m;
                        z_s <= a_s;
                    end else if (a_m >= b_m) begin
                        pre_sum <= a_m - b_m;
                        z_s <= a_s;
                    end else begin
                        pre_sum <= b_m - a_m;
                        z_s <= b_s;
                    end
                    state <= ADD_1;
                end
                ADD_1: begin
                    if (pre_sum[27]) begin
                        z_m <= pre_sum[27:4];
                        guard <= pre_sum[3];
                        round_bit <= pre_sum[2];
                        sticky <= pre_sum[1] | pre_sum[0];
                        z_e <= z_e + 1;
                    end else begin
                        z_m <= pre_sum[26:3];
                        guard <= pre_sum[2];
                        round_bit <= pre_sum[1];
                        sticky <= pre_sum[0];
                    end
                    state <= NORMALISE_1;
                end
                NORMALISE_1: begin
                    if (z_m[23] == 0 && $signed(z_e) > -126) begin
                        z_e <= z_e - 1;
                        z_m <= {z_m[22:0], guard};
                        guard <= round_bit;
                        round_bit <= 0;
                    end else begin
                        state <= NORMALISE_2;
                    end
                end
                NORMALISE_2: begin
                    if ($signed(z_e) < -126) begin
                        z_e <= z_e + 1;
                        z_m <= {1'b0, z_m[23:1]};
                        guard <= z_m[0];
                        round_bit <= guard;
                        sticky <= sticky | round_bit;
                    end else begin
                        state <= ROUND;
                    end
                end
                ROUND: begin
                    if (guard && (round_bit | sticky | z_m[0])) begin
                        z_m <= z_m + 1;
                        if (z_m == 24'hffffff) z_e <= z_e + 1;
                    end
                    state <= PACK;
                end
                PACK: begin
                    z[22:0] <= z_m[22:0];
                    z[30:23] <= z_e[7:0] + 127;
                    z[31] <= z_s;
                    if ($signed(z_e) == -126 && z_m[23] == 0) z[30:23] <= 0;
                    if ($signed(z_e) == -126 && z_m[23:0] == 24'h0) z[31] <= 1'b0;
                    if ($signed(z_e) > 127) begin
                        z[22:0] <= 0;
                        z[30:23] <= 255;
                        z[31] <= z_s;
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