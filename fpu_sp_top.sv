module fpu_sp_top (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [3:0]   cmd,       // 0001=ADD, 0010=SUB, 0011=MUL, 0100=DIV
    input  logic [31:0]  din1,      // Operand 1
    input  logic [31:0]  din2,      // Operand 2
    input  logic         dval,      // Pulse to trigger operation
    output logic [31:0]  result,    // Result of operation
    output logic         rdy        // Ready flag
);

    // Command definitions
    localparam logic [3:0] CMD_ADD = 4'b0001;
    localparam logic [3:0] CMD_SUB = 4'b0010;
    localparam logic [3:0] CMD_MUL = 4'b0011;
    localparam logic [3:0] CMD_DIV = 4'b0100;

    // Wires for module outputs
    logic [31:0] add_res, sub_res, mul_res, div_res;
    logic        add_rdy, sub_rdy, mul_rdy, div_rdy;

    // Register
    logic [3:0] cmd_reg;
    logic add_dval, sub_dval, mul_dval, div_dval;

    // Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cmd_reg <= 4'b0000;
        else if (dval)
            cmd_reg <= cmd;
    end

    // Generate dval pulses for each operation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            add_dval <= 1'b0;
            sub_dval <= 1'b0;
            mul_dval <= 1'b0;
            div_dval <= 1'b0;
        end else begin
            add_dval <= dval && (cmd == CMD_ADD);
            sub_dval <= dval && (cmd == CMD_SUB);
            mul_dval <= dval && (cmd == CMD_MUL);
            div_dval <= dval && (cmd == CMD_DIV);
        end
    end

    // Output mux based on registered command
    always_comb begin
        case (cmd_reg)
            CMD_ADD: begin
                result = add_res;
                rdy    = add_rdy;
            end
            CMD_SUB: begin
                result = sub_res;
                rdy    = sub_rdy;
            end
            CMD_MUL: begin
                result = mul_res;
                rdy    = mul_rdy;
            end
            CMD_DIV: begin
                result = div_res;
                rdy    = div_rdy;
            end
            default: begin
                result = 32'd0;
                rdy    = 1'b0;
            end
        endcase
    end

    // Instantiate operation modules
    fpu_sp_add u_add (
        .clk    (clk),
        .rst_n  (rst_n),
        .din1   (din1),
        .din2   (din2),
        .dval   (add_dval),
        .result (add_res),
        .rdy    (add_rdy)
    );

    fpu_sp_sub u_sub (
        .clk    (clk),
        .rst_n  (rst_n),
        .din1   (din1),
        .din2   (din2),
        .dval   (sub_dval),
        .result (sub_res),
        .rdy    (sub_rdy)
    );

    fpu_sp_mul u_mul (
        .clk    (clk),
        .rst_n  (rst_n),
        .din1   (din1),
        .din2   (din2),
        .dval   (mul_dval),
        .result (mul_res),
        .rdy    (mul_rdy)
    );

    fpu_sp_div u_div (
        .clk    (clk),
        .rst_n  (rst_n),
        .din1   (din1),
        .din2   (din2),
        .dval   (div_dval),
        .result (div_res),
        .rdy    (div_rdy)
    );

endmodule
