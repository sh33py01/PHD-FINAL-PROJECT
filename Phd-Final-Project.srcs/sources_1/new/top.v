module top(
    input  wire CLK100MHZ,
    input  wire [3:0] btn,
    output wire ja_0,
    output reg  [3:0] led
);

    // Heartbeat
    reg [25:0] div = 0;
    always @(posedge CLK100MHZ) div <= div + 1;
    always @(posedge CLK100MHZ) led[0] <= div[25];

    // Button debouncing
    reg [3:0] btn_prev = 0;
    reg [3:0] btn_stable = 0;
    reg [19:0] btn_cnt [0:3];
    reg [1:0] channel = 0;
    integer i;
    always @(posedge CLK100MHZ) begin
        for (i = 0; i < 4; i = i + 1) begin
            if (btn[i] != btn_stable[i]) begin
                if (btn_cnt[i] == 500000) begin
                    btn_stable[i] <= ~btn_stable[i];
                    btn_cnt[i] <= 0;
                end else begin
                    btn_cnt[i] <= btn_cnt[i] + 1;
                end
            end else begin
                btn_cnt[i] <= 0;
            end
        end
        btn_prev <= btn_stable;
        if (btn_stable[0] & ~btn_prev[0]) channel <= 0;
        if (btn_stable[1] & ~btn_prev[1]) channel <= 1;
        if (btn_stable[2] & ~btn_prev[2]) channel <= 2;
        if (btn_stable[3] & ~btn_prev[3]) channel <= 3;
    end

    // XADC wizard (configured for internal sensors)
    wire [15:0] xadc_do_out;
    wire        xadc_drdy_out;
    wire [4:0]  xadc_channel_out;
    wire        xadc_eoc_out;
    wire        xadc_eos_out;
    wire        xadc_busy_out;
    reg  [6:0]  daddr_in = 7'd0;
    reg         den_in   = 1'b0;
    wire        dwe_in   = 1'b0;
    wire [15:0] di_in    = 16'd0;
    wire        reset_in = 1'b0;

    xadc_wiz_0 xadc_inst (
        .dclk_in(CLK100MHZ),
        .reset_in(reset_in),
        .daddr_in(daddr_in),
        .den_in(den_in),
        .dwe_in(dwe_in),
        .di_in(di_in),
        .do_out(xadc_do_out),
        .drdy_out(xadc_drdy_out),
        .busy_out(xadc_busy_out),
        .channel_out(xadc_channel_out),
        .eoc_out(xadc_eoc_out),
        .eos_out(xadc_eos_out),
        .vp_in(1'b0),
        .vn_in(1'b0),
        .alarm_out(),
        .ot_out(),
        .user_temp_alarm_out(),
        .vccint_alarm_out(),
        .vccaux_alarm_out()
    );

    // Single-channel reader with button-selected address
    reg [1:0] rd_state = 0;
    reg [15:0] sample = 16'h1000;
    reg        ready = 0;
    reg [23:0] timeout = 0;

    always @(posedge CLK100MHZ) begin
        den_in <= 1'b0;
        ready <= 1'b0;

    case (rd_state)
        0: begin
            case (channel)
                0: daddr_in <= 7'h00;
                1: daddr_in <= 7'h01;
                2: daddr_in <= 7'h02;
                3: daddr_in <= 7'h03;
            endcase
            rd_state <= 1;
            timeout  <= 0;
        end
        1: begin
            if (!xadc_busy_out) begin
                den_in   <= 1'b1;
                rd_state <= 2;
            end
        end
        2: begin
            if (xadc_drdy_out) begin
                sample   <= xadc_do_out;
                ready    <= 1'b1;
                rd_state <= 0;
            end else if (timeout > 100000) begin
                rd_state <= 0;
            end else begin
                timeout <= timeout + 1;
            end
        end
    endcase 
    end

    // LED1: visible blink for read attempts (~2 Hz)
    reg [25:0] blink1;
    always @(posedge CLK100MHZ) begin
        if (rd_state == 0) blink1 <= blink1 + 1;
        if (blink1 == 25000000) begin
            led[1] <= ~led[1];
            blink1 <= 0;
        end
    end

    // UART transmitter @115200
    localparam BAUD_DIV = 868;
    reg [15:0] baud_cnt = 0;
    reg [3:0]  bit_cnt  = 0;
    reg [9:0]  shifter  = 10'b1111111111;
    reg        busy     = 0;
    assign ja_0 = shifter[0];

    task start_uart_byte(input [7:0] b);
    begin
        shifter <= {1'b1, b, 1'b0};
        bit_cnt <= 10;
        baud_cnt <= 0;
        busy <= 1;
    end
    endtask

    reg sending = 0;
    reg [2:0] byte_idx = 0;
    reg [23:0] fb_timer = 0;

    always @(posedge CLK100MHZ) begin
        if (busy) begin
            if (baud_cnt == BAUD_DIV-1) begin
                baud_cnt <= 0;
                shifter <= {1'b1, shifter[9:1]};
                bit_cnt <= bit_cnt - 1;
                if (bit_cnt == 1) busy <= 0;
            end else begin
                baud_cnt <= baud_cnt + 1;
            end
        end

        fb_timer <= fb_timer + 1;
        if (!busy && !sending) begin
            if (ready || fb_timer > 50000) begin
                fb_timer <= 0;
                sending <= 1;
                byte_idx <= 0;
            end
        end

        if (sending && !busy) begin
            case (byte_idx)
                0: begin start_uart_byte(8'hAA); byte_idx <= 1; end
                1: begin start_uart_byte(8'h55); byte_idx <= 2; end
                2: begin start_uart_byte({4'b0, channel}); byte_idx <= 3; end
                3: begin start_uart_byte(sample[15:8]); byte_idx <= 4; end
                4: begin
                    start_uart_byte(sample[7:0]);
                    byte_idx <= 0;
                    sending <= 0;
                end
            endcase
        end
    end

    // LED2: system alive (1 Hz)
    reg [26:0] alive;
    always @(posedge CLK100MHZ) begin
        alive <= alive + 1;
        if (alive == 50000000) begin
            led[2] <= ~led[2];
            alive <= 0;
        end
    end

    // LED3: DRDY activity (fast blink)
    always @(posedge CLK100MHZ) begin
        if (xadc_drdy_out) led[3] <= ~led[3];
    end

endmodule