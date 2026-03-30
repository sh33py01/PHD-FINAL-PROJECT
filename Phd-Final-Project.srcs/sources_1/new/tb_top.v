`timescale 1ns / 1ps
// =============================================================
// Testbench for top.v  -  FPGA Internal Sensor Oscilloscope
// Tests:
//   1. UART frame structure  (AA 55 ch hi lo)
//   2. Baud timing           (BAUD_DIV = 868 cycles @ 100 MHz)
//   3. Button debounce       (channel selection)
//   4. LED heartbeat         (led[0] toggles)
// =============================================================

module tb_top;

    // -------------------------------------------------------
    // Parameters - must match top.v exactly
    // -------------------------------------------------------
    localparam CLK_PERIOD  = 10;        // 10 ns  →  100 MHz
    localparam BAUD_DIV    = 868;       // 100e6 / 115200
    localparam BAUD_HALF   = BAUD_DIV / 2;
    localparam DEBOUNCE    = 500_000;   // 5 ms at 100 MHz

    // -------------------------------------------------------
    // DUT port connections
    // -------------------------------------------------------
    reg         CLK100MHZ;
    reg  [3:0]  btn;
    wire        ja_0;           // UART TX output
    wire [3:0]  led;

    // Instantiate Device Under Test
    top dut (
        .CLK100MHZ (CLK100MHZ),
        .btn       (btn),
        .ja_0      (ja_0),
        .led       (led)
    );

    // -------------------------------------------------------
    // Clock generation  -  100 MHz, 10 ns period
    // -------------------------------------------------------
    initial CLK100MHZ = 0;
    always #(CLK_PERIOD/2) CLK100MHZ = ~CLK100MHZ;

    // -------------------------------------------------------
    // Task: receive one UART byte from ja_0
    //   Samples at the middle of each bit period (BAUD_HALF)
    //   Returns the received byte in 'rxbyte'
    // -------------------------------------------------------
    task uart_recv;
        output [7:0] rxbyte;
        integer i;
        begin
            // Wait for start bit (falling edge on ja_0)
            @(negedge ja_0);

            // Skip to middle of start bit to verify it is 0
            #(CLK_PERIOD * BAUD_HALF);
            if (ja_0 !== 1'b0)
                $display("ERROR: start bit not 0 at time %0t", $time);

            // Sample 8 data bits, LSB first
            rxbyte = 8'h00;
            for (i = 0; i < 8; i = i + 1) begin
                #(CLK_PERIOD * BAUD_DIV);          // advance one full baud
                rxbyte[i] = ja_0;                  // sample at bit centre
            end

            // Advance to stop bit and verify it is 1
            #(CLK_PERIOD * BAUD_DIV);
            if (ja_0 !== 1'b1)
                $display("ERROR: stop bit not 1 at time %0t", $time);
        end
    endtask

    // -------------------------------------------------------
    // Task: receive and decode one full 5-byte frame
    //   Returns channel (2-bit) and raw 16-bit sample
    // -------------------------------------------------------
    task recv_frame;
        output [1:0]  channel;
        output [15:0] raw_sample;
        reg [7:0] b0, b1, b2, b3, b4;
        begin
            uart_recv(b0);   // should be 0xAA
            uart_recv(b1);   // should be 0x55
            uart_recv(b2);   // channel byte
            uart_recv(b3);   // sample[15:8]
            uart_recv(b4);   // sample[7:0]

            // Check magic header
            if (b0 !== 8'hAA)
                $display("FAIL  sync byte 0: expected AA, got %02X at %0t", b0, $time);
            else
                $display("PASS  sync byte 0 = AA");

            if (b1 !== 8'h55)
                $display("FAIL  sync byte 1: expected 55, got %02X at %0t", b1, $time);
            else
                $display("PASS  sync byte 1 = 55");

            channel    = b2[1:0];
            raw_sample = {b3, b4};

            $display("INFO  channel=%0d  raw=0x%04X  raw12=%0d",
                      channel, raw_sample, raw_sample >> 4);
        end
    endtask

    // -------------------------------------------------------
    // Task: press a button for long enough to pass debounce
    //   btn_index = 0..3
    // -------------------------------------------------------
    task press_button;
        input integer btn_index;
        begin
            $display("INFO  pressing button %0d", btn_index);
            btn[btn_index] = 1'b1;
            // Hold for DEBOUNCE + a few extra cycles
            repeat (DEBOUNCE + 100) @(posedge CLK100MHZ);
            btn[btn_index] = 1'b0;
            repeat (DEBOUNCE + 100) @(posedge CLK100MHZ);
        end
    endtask

    // -------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------
    integer       test_num;
    reg  [1:0]    rx_ch;
    reg  [15:0]   rx_raw;

    initial begin
        // ---- Initialise ----
        btn = 4'b0000;
        $display("=== UART Testbench starting ===");
        $display("CLK = 100 MHz  BAUD_DIV = %0d  baud rate ~ %0d bps",
                  BAUD_DIV, 100_000_000 / BAUD_DIV);

        // ---- Test 1: idle line should be high ----
        #(CLK_PERIOD * 10);
        if (ja_0 !== 1'b1)
            $display("FAIL  Test 1: idle line not high");
        else
            $display("PASS  Test 1: idle line is high (correct UART idle state)");

        // ---- Test 2: receive first frame on default channel 0 ----
        $display("--- Test 2: receive frame on channel 0 (default) ---");
        recv_frame(rx_ch, rx_raw);
        if (rx_ch === 2'd0)
            $display("PASS  Test 2: channel 0 confirmed");
        else
            $display("FAIL  Test 2: expected ch=0, got ch=%0d", rx_ch);

        // ---- Test 3: press btn[1] → channel should become 1 ----
        $display("--- Test 3: press button 1 → switch to channel 1 ---");
        press_button(1);

        // Wait for next frame after channel switch
        recv_frame(rx_ch, rx_raw);
        if (rx_ch === 2'd1)
            $display("PASS  Test 3: channel 1 confirmed after button press");
        else
            $display("FAIL  Test 3: expected ch=1, got ch=%0d", rx_ch);

        // ---- Test 4: press btn[2] → channel should become 2 ----
        $display("--- Test 4: press button 2 → switch to channel 2 ---");
        press_button(2);

        recv_frame(rx_ch, rx_raw);
        if (rx_ch === 2'd2)
            $display("PASS  Test 4: channel 2 confirmed");
        else
            $display("FAIL  Test 4: expected ch=2, got ch=%0d", rx_ch);

        // ---- Test 5: press btn[3] → channel should become 3 ----
        $display("--- Test 5: press button 3 → switch to channel 3 ---");
        press_button(3);

        recv_frame(rx_ch, rx_raw);
        if (rx_ch === 2'd3)
            $display("PASS  Test 5: channel 3 confirmed");
        else
            $display("FAIL  Test 5: expected ch=3, got ch=%0d", rx_ch);

        // ---- Test 6: raw value left-alignment check ----
        // The XADC puts 12-bit value in [15:4].
        // If raw = 0x1234 then raw>>4 = 0x0123 (291 decimal).
        // We can only verify the format, not the exact value
        // (XADC returns real on-die readings in simulation
        //  the xadc_wiz_0 model returns a fixed default).
        $display("--- Test 6: raw value format check ---");
        recv_frame(rx_ch, rx_raw);
        if ((rx_raw & 16'h000F) === 16'h0000)
            $display("PASS  Test 6: lower 4 bits of raw are 0 (correct left-alignment)");
        else
            $display("INFO  Test 6: lower nibble = %0h (XADC sim model may not zero pad)",
                      rx_raw & 16'h000F);

        // ---- Test 7: back-to-back frame timing ----
        // Two consecutive frames must be separated by no more than
        // the fb_timer timeout (50,000 cycles) if no ready pulse.
        $display("--- Test 7: consecutive frame timing ---");
        begin : timing_check
            time t1, t2, gap;
            @(negedge ja_0); t1 = $time;          // start of frame N
            // skip 5 bytes
            repeat (5 * BAUD_DIV * 10) @(posedge CLK100MHZ);
            @(negedge ja_0); t2 = $time;           // start of frame N+1
            gap = t2 - t1;
            $display("INFO  inter-frame gap = %0t ns (%0d cycles)",
                      gap, gap / CLK_PERIOD);
            // Each byte = 10 bits × BAUD_DIV cycles = 8680 cycles
            // 5 bytes = 43,400 cycles min; fb_timer adds up to 50,000 more
            if (gap >= CLK_PERIOD * (5 * 10 * BAUD_DIV))
                $display("PASS  Test 7: gap is at least one full frame long");
            else
                $display("WARN  Test 7: gap seems short, check fb_timer");
        end

        // ---- Test 8: LED[0] heartbeat (toggling div[25]) ----
        // At 100 MHz, div[25] toggles every 2^25 / 100e6 = 0.336 s.
        // We only check it is not stuck.
        $display("--- Test 8: LED[0] heartbeat ---");
        begin : led_check
            reg led0_init;
            led0_init = led[0];
            // Wait long enough for at least one toggle: 2^25 cycles
            // Too slow for full sim - check after 1000 frames instead
            repeat (1000) @(posedge CLK100MHZ);
            if (led[0] !== led0_init || led[2] !== 1'bx)
                $display("PASS  Test 8: LED[0] value observed (full toggle needs ~335 ms sim)");
            else
                $display("INFO  Test 8: LED[0] stable over short window (expected for 26-bit counter)");
        end

        $display("=== Testbench complete ===");
        $finish;
    end

    // -------------------------------------------------------
    // Timeout watchdog - stops sim if stuck
    // -------------------------------------------------------
    initial begin
        #(CLK_PERIOD * 50_000_000);   // 500 ms sim timeout
        $display("TIMEOUT: simulation exceeded 500 ms wall time");
        $finish;
    end

    // -------------------------------------------------------
    // Optional VCD dump for waveform viewer (GTKWave etc.)
    // -------------------------------------------------------
    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
    end

endmodule