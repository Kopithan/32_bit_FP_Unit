module fpu_sp_led_display (
    input  logic        clk,        // 50MHz clock
    input  logic        rst_n,      // Active low reset
    input  logic [1:0]  op_sel,     // Operation select: 00=ADD, 01=SUB, 10=MUL, 11=DIV
    input  logic [1:0]  test_sel,   // Test case select: 00=Test1, 01=Test2, 10=Test3, 11=Test4
    input  logic        start_btn,  // Push button to start operation
    output logic [7:0]  leds        
);

    // ----------------------------
    // Test Cases - Multiple Number Combinations
    // ----------------------------
    logic [31:0] din1, din2;

    always_comb begin
        case(test_sel)
            2'b00: begin
                din1 = 32'h40400000; // 3.0
                din2 = 32'h3F800000; // 1.0
            end
            2'b01: begin
                din1 = 32'h40A00000; // 5.0
                din2 = 32'h40000000; // 2.0
            end
            2'b10: begin
                din1 = 32'h41200000; // 10.0
                din2 = 32'h40800000; // 4.0
            end
            2'b11: begin
                din1 = 32'h40D00000; // 6.5
                din2 = 32'h3FC00000; // 1.5
            end
            default: begin
                din1 = 32'h00000000;
                din2 = 32'h00000000;
            end
        endcase
    end

    // ----------------------------
    // FPU Interface Signals
    // ----------------------------
    logic [3:0]  fpu_cmd;
    logic        fpu_dval;
    logic [31:0] fpu_result;
    logic        fpu_rdy;

    // Command encoding
    localparam logic [3:0] CMD_ADD = 4'b0001;
    localparam logic [3:0] CMD_SUB = 4'b0010;
    localparam logic [3:0] CMD_MUL = 4'b0011;
    localparam logic [3:0] CMD_DIV = 4'b0100;

    // Convert 2-bit op_sel to 4-bit FPU command
    always_comb begin
        case(op_sel)
            2'b00: fpu_cmd = CMD_ADD;
            2'b01: fpu_cmd = CMD_SUB;
            2'b10: fpu_cmd = CMD_MUL;
            2'b11: fpu_cmd = CMD_DIV;
            default: fpu_cmd = CMD_ADD;
        endcase
    end

    // ----------------------------
    // Button Debouncing & Edge Detection
    // ----------------------------
    logic [19:0] debounce_cnt;
    logic [2:0]  btn_sync;
    logic        btn_stable, btn_stable_prev;
    logic        btn_pulse;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_sync        <= 3'b000;
            debounce_cnt    <= 20'd0;
            btn_stable      <= 1'b0;
            btn_stable_prev <= 1'b0;
        end else begin
            // Synchronizer chain
            btn_sync <= {btn_sync[1:0], start_btn};

            // Debouncer (10ms at 50MHz)
            if (btn_sync[2] == btn_sync[1]) begin
                if (debounce_cnt < 20'd500_000) begin
                    debounce_cnt <= debounce_cnt + 1;
                end else begin
                    btn_stable <= btn_sync[2];
                end
            end else begin
                debounce_cnt <= 20'd0;
            end

            // Edge detector
            btn_stable_prev <= btn_stable;
        end
    end

    assign btn_pulse = btn_stable & ~btn_stable_prev;

    // ----------------------------
    // FPU Controller State Machine
    // ----------------------------
    typedef enum logic [1:0] {
        FPU_IDLE   = 2'd0,
        FPU_START  = 2'd1,
        FPU_WAIT   = 2'd2,
        FPU_DONE   = 2'd3
    } fpu_state_t;

    fpu_state_t fpu_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fpu_state <= FPU_IDLE;
            fpu_dval  <= 1'b0;
        end else begin
            case (fpu_state)
                FPU_IDLE: begin
                    fpu_dval <= 1'b0;
                    if (btn_pulse) fpu_state <= FPU_START;
                end
                FPU_START: begin
                    fpu_dval  <= 1'b1;
                    fpu_state <= FPU_WAIT;
                end
                FPU_WAIT: begin
                    fpu_dval <= 1'b0;
                    if (fpu_rdy) fpu_state <= FPU_DONE;
                end
                FPU_DONE: fpu_state <= FPU_IDLE;
                default: fpu_state <= FPU_IDLE;
            endcase
        end
    end

    // ----------------------------
    // Instantiate FPU
    // ----------------------------
    fpu_sp_top u_fpu (
        .clk    (clk),
        .rst_n  (rst_n),
        .cmd    (fpu_cmd),
        .din1   (din1),
        .din2   (din2),
        .dval   (fpu_dval),
        .result (fpu_result),
        .rdy    (fpu_rdy)
    );

    // ----------------------------
    // LED Display Controller
    // ----------------------------
    typedef enum logic [2:0] {
        LED_IDLE   = 3'd0,
        LED_WAIT   = 3'd1,
        LED_BYTE0  = 3'd2,
        LED_BYTE1  = 3'd3,
        LED_BYTE2  = 3'd4,
        LED_BYTE3  = 3'd5
    } led_state_t;

    led_state_t  led_state;
    logic [31:0] result_latched;
    logic [27:0] delay_cnt;

    localparam DISPLAY_TIME = 28'd25_000_000; // 0.5 sec at 50MHz

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led_state      <= LED_IDLE;
            leds           <= 8'hFF;
            delay_cnt      <= 28'd0;
            result_latched <= 32'd0;
        end else begin
            case (led_state)
                LED_IDLE: begin
                    leds      <= 8'h00;
                    delay_cnt <= 28'd0;
                    if (btn_pulse) led_state <= LED_WAIT;
                end
                LED_WAIT: begin
                    leds <= 8'hAA;
                    if (fpu_rdy) begin
                        result_latched <= fpu_result;
                        delay_cnt      <= 28'd0;
                        led_state      <= LED_BYTE0;
                    end
                end
                LED_BYTE0: begin
                    leds <= result_latched[31:24];
                    if (delay_cnt >= DISPLAY_TIME-1) begin
                        delay_cnt <= 28'd0;
                        led_state <= LED_BYTE1;
                    end else delay_cnt <= delay_cnt + 1;
                end
                LED_BYTE1: begin
                    leds <= result_latched[23:16];
                    if (delay_cnt >= DISPLAY_TIME-1) begin
                        delay_cnt <= 28'd0;
                        led_state <= LED_BYTE2;
                    end else delay_cnt <= delay_cnt + 1;
                end
                LED_BYTE2: begin
                    leds <= result_latched[15:8];
                    if (delay_cnt >= DISPLAY_TIME-1) begin
                        delay_cnt <= 28'd0;
                        led_state <= LED_BYTE3;
                    end else delay_cnt <= delay_cnt + 1;
                end
                LED_BYTE3: begin
                    leds <= result_latched[7:0];
                    if (delay_cnt >= DISPLAY_TIME-1) begin
                        delay_cnt <= 28'd0;
                        led_state <= LED_IDLE;
                    end else delay_cnt <= delay_cnt + 1;
                end
                default: begin
                    led_state <= LED_IDLE;
                    leds      <= 8'h55;
                end
            endcase
        end
    end

endmodule
