module fpu_sp_mul (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [31:0]  din1,
    input  logic [31:0]  din2,
    input  logic         dval,
    output logic [31:0]  result,
    output logic         rdy
);

    typedef enum logic [3:0] {
        WAIT_REQ     = 4'd0,
        UNPACK       = 4'd1,
        SPECIAL_CASES= 4'd2,
        NORMALISE_A  = 4'd3,
        NORMALISE_B  = 4'd4,
        MULTIPLY_0   = 4'd5,
        MULTIPLY_1   = 4'd6,
        NORMALISE_1  = 4'd7,
        NORMALISE_2  = 4'd8,
        ROUND        = 4'd9,
        PACK         = 4'd10,
        OUT_RDY      = 4'd11
    } state_t;

    state_t      state;

    logic [31:0] a, b, z;
    logic [23:0] a_m, b_m, z_m;
    logic [9:0]  a_e, b_e, z_e;
    logic        a_s, b_s, z_s;
    logic        guard, round_bit, sticky;
    logic [47:0] product;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= WAIT_REQ;
            rdy    <= 1'b0;
            result <= 32'b0;
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
                    if ((a_e == 128 && a_m != 0) || (b_e == 128 && b_m != 0)) begin
                        z[31]   <= 0;
                        z[30:23]<= 255;
                        z[22]   <= 1;
                        z[21:0] <= 0;
                        state   <= OUT_RDY;
                    end else if (a_e == 128 && a_m == 0) begin
                        z[31]   <= a_s ^ b_s;
                        z[30:23]<= 255;
                        z[22:0] <= 0;
                        if ((($signed(b_e) == -127) && (b_m == 0)) || (b_e == 128 && b_m == 0)) begin
                            z[31]   <= 0;
                            z[30:23]<= 255;
                            z[22]   <= 1;
                            z[21:0] <= 0;
                        end
                        state <= OUT_RDY;
                    end else if (b_e == 128) begin
                        z[31]   <= a_s ^ b_s;
                        z[30:23]<= 255;
                        z[22:0] <= 0;
                        if ((($signed(a_e) == -127) && (a_m == 0)) || (a_e == 128 && a_m == 0)) begin
                            z[31]   <= 0;
                            z[30:23]<= 255;
                            z[22]   <= 1;
                            z[21:0] <= 0;
                        end
                        state <= OUT_RDY;
                    end else if (($signed(a_e) == -127) && (a_m == 0)) begin
                        z[31]   <= a_s ^ b_s;
                        z[30:23]<= 0;
                        z[22:0] <= 0;
                        state   <= OUT_RDY;
                    end else if (($signed(b_e) == -127) && (b_m == 0)) begin
                        z[31]   <= a_s ^ b_s;
                        z[30:23]<= 0;
                        z[22:0] <= 0;
                        state   <= OUT_RDY;
                    end else begin
                        if ($signed(a_e) == -127) begin
                            a_e <= -126;
                        end else begin
                            a_m[23] <= 1;
                        end
                        if ($signed(b_e) == -127) begin
                            b_e <= -126;
                        end else begin
                            b_m[23] <= 1;
                        end
                        state <= NORMALISE_A;
                    end
                end
                NORMALISE_A: begin
                    if (a_m[23]) begin
                        state <= NORMALISE_B;
                    end else begin
                        a_m <= a_m << 1;
                        a_e <= a_e - 1;
                        state <= NORMALISE_A;
                    end
                end
                NORMALISE_B: begin
                    if (b_m[23]) begin
                        state <= MULTIPLY_0;
                    end else begin
                        b_m <= b_m << 1;
                        b_e <= b_e - 1;
                        state <= NORMALISE_B;
                    end
                end
                MULTIPLY_0: begin
                    z_s <= a_s ^ b_s;
                    z_e <= a_e + b_e + 1;
                    product <= a_m * b_m;
                    state <= MULTIPLY_1;
                end
                MULTIPLY_1: begin
                    z_m      <= product[47:24];
                    guard    <= product[23];
                    round_bit<= product[22];
                    sticky   <= (product[21:0] != 0);
                    state    <= NORMALISE_1;
                end
                NORMALISE_1: begin
                    if (z_m[23] == 0) begin
                        z_e <= z_e - 1;
                        z_m <= z_m << 1;
                        z_m[0] <= guard;
                        guard  <= round_bit;
                        round_bit <= 0;
                        state <= NORMALISE_1;
                    end else begin
                        state <= NORMALISE_2;
                    end
                end
                NORMALISE_2: begin
                    if ($signed(z_e) < -126) begin
                        z_e <= z_e + 1;
                        z_m <= z_m >> 1;
                        guard <= z_m[0];
                        round_bit <= guard;
                        sticky <= sticky | round_bit;
                        state <= NORMALISE_2;
                    end else begin
                        state <= ROUND;
                    end
                end
                ROUND: begin
                    if (guard && (round_bit | sticky | z_m[0])) begin
                        z_m <= z_m + 1;
                        if (z_m == 24'hffffff) begin
                            z_e <= z_e + 1;
                        end
                    end
                    state <= PACK;
                end
                PACK: begin
                    z[22:0]  <= z_m[22:0];
                    z[30:23] <= z_e[7:0] + 127;
                    z[31]    <= z_s;
                    if ($signed(z_e) == -126 && z_m[23] == 0) begin
                        z[30:23] <= 0;
                    end
                    if ($signed(z_e) > 127) begin
                        z[22:0]  <= 0;
                        z[30:23] <= 255;
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