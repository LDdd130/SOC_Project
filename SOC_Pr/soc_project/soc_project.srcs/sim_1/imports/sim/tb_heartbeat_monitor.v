`timescale 1ns / 1ps

module tb_heartbeat_monitor_core;

    localparam integer CLK_PERIOD_NS = 10;

    reg         clk;
    reg         reset;
    reg         enable;
    reg  [2:0]  heartbeat_async;
    reg  [2:0]  device_enable;
    reg  [31:0] timeout0;
    reg  [31:0] timeout1;
    reg  [31:0] timeout2;
    reg         clear_all_pulse;
    reg         auto_recover;

    wire [2:0]  alive;
    wire [2:0]  timeout;
    wire [31:0] last_count0;
    wire [31:0] last_count1;
    wire [31:0] last_count2;
    wire [2:0]  timeout_event;

    integer error_count;

    heartbeat_monitor_core dut (
        .clk              (clk),
        .reset            (reset),
        .enable           (enable),
        .heartbeat_async  (heartbeat_async),
        .device_enable    (device_enable),
        .timeout0         (timeout0),
        .timeout1         (timeout1),
        .timeout2         (timeout2),
        .clear_all_pulse  (clear_all_pulse),
        .auto_recover     (auto_recover),
        .alive            (alive),
        .timeout          (timeout),
        .last_count0      (last_count0),
        .last_count1      (last_count1),
        .last_count2      (last_count2),
        .timeout_event    (timeout_event)
    );

    // 100 MHz clock
    initial clk = 1'b0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Self-checking tasks
    // -------------------------------------------------------------------------
    task check_bit;
        input actual;
        input expected;
        input [8*100-1:0] message;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s | actual=%b expected=%b @ %0t",
                         message, actual, expected, $time);
                error_count = error_count + 1;
            end
            else begin
                $display("[PASS] %0s @ %0t", message, $time);
            end
        end
    endtask

    task check_vec3;
        input [2:0] actual;
        input [2:0] expected;
        input [8*100-1:0] message;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s | actual=%03b expected=%03b @ %0t",
                         message, actual, expected, $time);
                error_count = error_count + 1;
            end
            else begin
                $display("[PASS] %0s @ %0t", message, $time);
            end
        end
    endtask

    task check_word;
        input [31:0] actual;
        input [31:0] expected;
        input [8*100-1:0] message;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s | actual=%0d(0x%08h) expected=%0d(0x%08h) @ %0t",
                         message, actual, actual, expected, expected, $time);
                error_count = error_count + 1;
            end
            else begin
                $display("[PASS] %0s @ %0t", message, $time);
            end
        end
    endtask

    task wait_clocks;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1)
                @(posedge clk);
            #1;
        end
    endtask

    // CLEAR_ALL을 정확히 한 클럭 동안 인가한다.
    task pulse_clear_all;
        begin
            @(negedge clk);
            clear_all_pulse = 1'b1;
            @(negedge clk);
            clear_all_pulse = 1'b0;
            #1;
        end
    endtask

    // 지정한 장치 한 개에 비동기 Heartbeat를 인가한다.
    // 3개의 상승 에지를 유지하여 2FF 동기화와 edge detector를 통과시킨다.
    task send_heartbeat;
        input integer channel;
        begin
            @(negedge clk);
            heartbeat_async[channel] = 1'b1;
            repeat (3) @(negedge clk);
            heartbeat_async[channel] = 1'b0;
            #1;
        end
    endtask

    // 세 장치에 동시에 Heartbeat를 인가한다.
    task send_all_heartbeats;
        begin
            @(negedge clk);
            heartbeat_async = 3'b111;
            repeat (3) @(negedge clk);
            heartbeat_async = 3'b000;
            #1;
        end
    endtask

    initial begin
        error_count      = 0;
        reset            = 1'b1;
        enable           = 1'b0;
        heartbeat_async  = 3'b000;
        device_enable    = 3'b000;
        timeout0         = 32'd0;
        timeout1         = 32'd0;
        timeout2         = 32'd0;
        clear_all_pulse  = 1'b0;
        auto_recover     = 1'b0;

        // ---------------------------------------------------------------------
        // 1. Reset / Disable 확인
        // ---------------------------------------------------------------------
        $display("\n[TEST 1] Reset and disabled outputs");
        wait_clocks(3);
        reset = 1'b0;
        wait_clocks(1);

        check_vec3(alive,         3'b000, "Reset: all alive outputs are 0");
        check_vec3(timeout,       3'b000, "Reset: all timeout outputs are 0");
        check_vec3(timeout_event, 3'b000, "Reset: all timeout events are 0");
        check_word(last_count0, 32'd0, "Reset: device0 count is 0");
        check_word(last_count1, 32'd0, "Reset: device1 count is 0");
        check_word(last_count2, 32'd0, "Reset: device2 count is 0");

        // ---------------------------------------------------------------------
        // 2. 세 장치 모두 Enable
        // ---------------------------------------------------------------------
        $display("\n[TEST 2] Enable all three devices");
        timeout0      = 32'd20;
        timeout1      = 32'd20;
        timeout2      = 32'd20;
        device_enable = 3'b111;
        enable        = 1'b1;
        wait_clocks(1);

        check_vec3(alive,   3'b111, "All enabled devices start alive");
        check_vec3(timeout, 3'b000, "No device is timed out after enable");

        // ---------------------------------------------------------------------
        // 3. 각 채널 Heartbeat가 자기 Counter만 초기화하는지 확인
        // ---------------------------------------------------------------------
        $display("\n[TEST 3] Independent heartbeat operation for device0, 1, 2");

        pulse_clear_all();
        send_heartbeat(0);
        check_word(last_count0, 32'd0, "Device0 heartbeat clears count0");
        check_word(last_count1, 32'd4, "Device0 heartbeat does not clear count1");
        check_word(last_count2, 32'd4, "Device0 heartbeat does not clear count2");
        check_vec3(timeout, 3'b000, "No timeout during device0 heartbeat test");

        pulse_clear_all();
        send_heartbeat(1);
        check_word(last_count0, 32'd4, "Device1 heartbeat does not clear count0");
        check_word(last_count1, 32'd0, "Device1 heartbeat clears count1");
        check_word(last_count2, 32'd4, "Device1 heartbeat does not clear count2");
        check_vec3(timeout, 3'b000, "No timeout during device1 heartbeat test");

        pulse_clear_all();
        send_heartbeat(2);
        check_word(last_count0, 32'd4, "Device2 heartbeat does not clear count0");
        check_word(last_count1, 32'd4, "Device2 heartbeat does not clear count1");
        check_word(last_count2, 32'd0, "Device2 heartbeat clears count2");
        check_vec3(timeout, 3'b000, "No timeout during device2 heartbeat test");

        // ---------------------------------------------------------------------
        // 4. 서로 다른 Timeout: Device0=4, Device1=5, Device2=7
        // ---------------------------------------------------------------------
        $display("\n[TEST 4] Different timeout values: 4, 5, 7 clocks");
        timeout0 = 32'd4;
        timeout1 = 32'd5;
        timeout2 = 32'd7;
        pulse_clear_all();

        wait_clocks(3);
        check_word(last_count0, 32'd3, "Before timeout: count0=3");
        check_word(last_count1, 32'd3, "Before timeout: count1=3");
        check_word(last_count2, 32'd3, "Before timeout: count2=3");
        check_vec3(timeout,       3'b000, "No timeout before minimum limit");
        check_vec3(timeout_event, 3'b000, "No timeout event before minimum limit");

        wait_clocks(1);
        check_vec3(timeout,       3'b001, "Count 4: only device0 times out");
        check_vec3(timeout_event, 3'b001, "Count 4: only device0 event pulses");
        check_vec3(alive,         3'b110, "Count 4: device0 alive goes low");

        wait_clocks(1);
        check_vec3(timeout,       3'b011, "Count 5: device0 and device1 timed out");
        check_vec3(timeout_event, 3'b010, "Count 5: only device1 event pulses");
        check_vec3(alive,         3'b100, "Count 5: only device2 remains alive");

        wait_clocks(1);
        check_vec3(timeout,       3'b011, "Count 6: timeout states remain latched");
        check_vec3(timeout_event, 3'b000, "Count 6: previous events do not repeat");

        wait_clocks(1);
        check_vec3(timeout,       3'b111, "Count 7: all three devices timed out");
        check_vec3(timeout_event, 3'b100, "Count 7: only device2 event pulses");
        check_vec3(alive,         3'b000, "Count 7: all alive outputs are low");

        wait_clocks(1);
        check_vec3(timeout_event, 3'b000, "Timeout events are one-clock pulses");

        // ---------------------------------------------------------------------
        // 5. AUTO_RECOVER=0: Heartbeat 수신 후에도 Timeout 유지
        // ---------------------------------------------------------------------
        $display("\n[TEST 5] AUTO_RECOVER=0 keeps timeout latched");
        auto_recover = 1'b0;
        send_all_heartbeats();

        check_word(last_count0, 32'd0, "All heartbeat: count0 clears");
        check_word(last_count1, 32'd0, "All heartbeat: count1 clears");
        check_word(last_count2, 32'd0, "All heartbeat: count2 clears");
        check_vec3(timeout, 3'b111, "AUTO_RECOVER=0 keeps all timeout states");
        check_vec3(alive,   3'b000, "Timed-out devices remain not alive");

        // Heartbeat Low 상태가 2FF와 edge detector까지 전달되도록 대기
        wait_clocks(3);

        // ---------------------------------------------------------------------
        // 6. AUTO_RECOVER=1: 세 장치 모두 Heartbeat로 복구
        // ---------------------------------------------------------------------
        $display("\n[TEST 6] AUTO_RECOVER=1 recovers all devices");
        auto_recover = 1'b1;
        send_all_heartbeats();

        check_word(last_count0, 32'd0, "Auto recovery clears count0");
        check_word(last_count1, 32'd0, "Auto recovery clears count1");
        check_word(last_count2, 32'd0, "Auto recovery clears count2");
        check_vec3(timeout,       3'b000, "AUTO_RECOVER=1 clears all timeouts");
        check_vec3(timeout_event, 3'b000, "Recovery does not create timeout event");
        check_vec3(alive,         3'b111, "All devices become alive after recovery");

        // ---------------------------------------------------------------------
        // 7. 세 장치 동시 Timeout
        // ---------------------------------------------------------------------
        $display("\n[TEST 7] Simultaneous timeout of all three devices");
        timeout0 = 32'd3;
        timeout1 = 32'd3;
        timeout2 = 32'd3;
        pulse_clear_all();

        wait_clocks(2);
        check_vec3(timeout,       3'b000, "Count 2: no simultaneous timeout yet");
        check_vec3(timeout_event, 3'b000, "Count 2: no simultaneous event yet");

        wait_clocks(1);
        check_vec3(timeout,       3'b111, "Count 3: all devices time out together");
        check_vec3(timeout_event, 3'b111, "Count 3: all timeout events pulse together");
        check_vec3(alive,         3'b000, "Simultaneous timeout clears all alive outputs");

        wait_clocks(1);
        check_vec3(timeout_event, 3'b000, "Simultaneous timeout event lasts one clock");

        // ---------------------------------------------------------------------
        // 8. Device 1만 비활성화
        // ---------------------------------------------------------------------
        $display("\n[TEST 8] Disable only device1");
        @(negedge clk);
        device_enable = 3'b101;
        pulse_clear_all();

        check_word(last_count0, 32'd0, "CLEAR_ALL clears enabled device0 counter");
        check_word(last_count1, 32'd0, "Disabled device1 counter stays 0");
        check_word(last_count2, 32'd0, "CLEAR_ALL clears enabled device2 counter");
        check_vec3(timeout,       3'b000, "Device disable and CLEAR_ALL clear timeouts");
        check_vec3(timeout_event, 3'b000, "Disabled device produces no event");
        check_vec3(alive,         3'b101, "Only device0 and device2 are alive");

        wait_clocks(1);
        check_word(last_count0, 32'd1, "Enabled device0 counter increments");
        check_word(last_count1, 32'd0, "Disabled device1 counter remains 0");
        check_word(last_count2, 32'd1, "Enabled device2 counter increments");

        // ---------------------------------------------------------------------
        // 9. timeout_setting=0을 세 장치 모두 1로 처리
        // ---------------------------------------------------------------------
        $display("\n[TEST 9] timeout_setting=0 is treated as 1 for all devices");
        @(negedge clk);
        device_enable = 3'b111;
        timeout0      = 32'd0;
        timeout1      = 32'd0;
        timeout2      = 32'd0;
        pulse_clear_all();

        wait_clocks(1);
        check_word(last_count0, 32'd1, "timeout0=0: count0 reaches effective limit 1");
        check_word(last_count1, 32'd1, "timeout1=0: count1 reaches effective limit 1");
        check_word(last_count2, 32'd1, "timeout2=0: count2 reaches effective limit 1");
        check_vec3(timeout,       3'b111, "timeout=0 causes all timeouts at first count");
        check_vec3(timeout_event, 3'b111, "timeout=0 creates all events once");
        check_vec3(alive,         3'b000, "timeout=0 makes all devices not alive");

        // ---------------------------------------------------------------------
        // 10. 전체 Disable과 재활성화
        // ---------------------------------------------------------------------
        $display("\n[TEST 10] Global disable and re-enable");
        @(negedge clk);
        enable = 1'b0;
        wait_clocks(1);

        check_word(last_count0, 32'd0, "Global disable clears count0");
        check_word(last_count1, 32'd0, "Global disable clears count1");
        check_word(last_count2, 32'd0, "Global disable clears count2");
        check_vec3(timeout,       3'b000, "Global disable clears all timeouts");
        check_vec3(timeout_event, 3'b000, "Global disable clears all events");
        check_vec3(alive,         3'b000, "Global disable forces all alive low");

        @(negedge clk);
        timeout0 = 32'd4;
        timeout1 = 32'd5;
        timeout2 = 32'd7;
        enable   = 1'b1;
        wait_clocks(1);

        check_word(last_count0, 32'd1, "Re-enable restarts count0 from zero");
        check_word(last_count1, 32'd1, "Re-enable restarts count1 from zero");
        check_word(last_count2, 32'd1, "Re-enable restarts count2 from zero");
        check_vec3(timeout, 3'b000, "Re-enable does not retain old timeout states");
        check_vec3(alive,   3'b111, "All devices are alive after re-enable");

        // ---------------------------------------------------------------------
        // Final result
        // ---------------------------------------------------------------------
        if (error_count == 0) begin
            $display("\n====================================================");
            $display(" ALL 3-CHANNEL HEARTBEAT CORE TESTS PASSED");
            $display("====================================================\n");
        end
        else begin
            $display("\n====================================================");
            $display(" TEST FAILED: %0d error(s)", error_count);
            $display("====================================================\n");
        end

        $finish;
    end

endmodule


// =============================================================================
// tb_heartbeat_monitor_axi
// -----------------------------------------------------------------------------
// heartbeat_monitor_axi용 Self-checking AXI4-Lite Testbench
//
// 검증 항목
//   1. Reset 기본값
//   2. AW/W 동시 및 독립 Handshake
//   3. TIMEOUT0~2 Write / Read-back
//   4. WSTRB Byte Write
//   5. CTRL ENABLE / AUTO_RECOVER / CLEAR_ALL(W1P)
//   6. STATUS, LAST_COUNT Read-only
//   7. IRQ_EN Read / Write
//   8. Timeout Event -> IRQ_STATUS Latch -> Level IRQ
//   9. IRQ_STATUS W1C 및 Timeout 상태와의 독립성
//  10. CLEAR_ALL이 IRQ_STATUS를 지우지 않는지 확인
//  11. IRQ_STATUS 일부 비트 W1C
//  12. IRQ_EN에 의한 IRQ 출력 Mask
//  13. AXI를 통한 AUTO_RECOVER=0/1 동작
// =============================================================================
module tb_heartbeat_monitor_axi;

    localparam integer DATA_WIDTH = 32;
    localparam integer ADDR_WIDTH = 6;

    localparam [5:0] ADDR_CTRL        = 6'h00;
    localparam [5:0] ADDR_STATUS      = 6'h04;
    localparam [5:0] ADDR_TIMEOUT0    = 6'h08;
    localparam [5:0] ADDR_TIMEOUT1    = 6'h0C;
    localparam [5:0] ADDR_TIMEOUT2    = 6'h10;
    localparam [5:0] ADDR_LAST_COUNT0 = 6'h14;
    localparam [5:0] ADDR_LAST_COUNT1 = 6'h18;
    localparam [5:0] ADDR_LAST_COUNT2 = 6'h1C;
    localparam [5:0] ADDR_IRQ_EN      = 6'h20;
    localparam [5:0] ADDR_IRQ_STATUS  = 6'h24;

    // -------------------------------------------------------------------------
    // DUT I/O
    // -------------------------------------------------------------------------
    reg  [2:0] heartbeat_async;
    wire [2:0] alive;
    wire [2:0] timeout;
    wire       irq;

    reg                              S_AXI_ACLK;
    reg                              S_AXI_ARESETN;
    reg  [ADDR_WIDTH-1:0]            S_AXI_AWADDR;
    reg  [2:0]                       S_AXI_AWPROT;
    reg                              S_AXI_AWVALID;
    wire                             S_AXI_AWREADY;
    reg  [DATA_WIDTH-1:0]            S_AXI_WDATA;
    reg  [(DATA_WIDTH/8)-1:0]        S_AXI_WSTRB;
    reg                              S_AXI_WVALID;
    wire                             S_AXI_WREADY;
    wire [1:0]                       S_AXI_BRESP;
    wire                             S_AXI_BVALID;
    reg                              S_AXI_BREADY;
    reg  [ADDR_WIDTH-1:0]            S_AXI_ARADDR;
    reg  [2:0]                       S_AXI_ARPROT;
    reg                              S_AXI_ARVALID;
    wire                             S_AXI_ARREADY;
    wire [DATA_WIDTH-1:0]            S_AXI_RDATA;
    wire [1:0]                       S_AXI_RRESP;
    wire                             S_AXI_RVALID;
    reg                              S_AXI_RREADY;

    integer error_count;
    integer clear_pulse_count;
    integer clear_width_error;
    integer clear_effect_error;
    reg     clear_pulse_previous;
    reg [31:0] read_value;
    integer before_clear_count;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    heartbeat_monitor_axi #(
        .C_S_AXI_DATA_WIDTH (DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH (ADDR_WIDTH)
    ) dut (
        .heartbeat_async (heartbeat_async),
        .alive           (alive),
        .timeout         (timeout),
        .irq             (irq),

        .S_AXI_ACLK      (S_AXI_ACLK),
        .S_AXI_ARESETN   (S_AXI_ARESETN),
        .S_AXI_AWADDR    (S_AXI_AWADDR),
        .S_AXI_AWPROT    (S_AXI_AWPROT),
        .S_AXI_AWVALID   (S_AXI_AWVALID),
        .S_AXI_AWREADY   (S_AXI_AWREADY),
        .S_AXI_WDATA     (S_AXI_WDATA),
        .S_AXI_WSTRB     (S_AXI_WSTRB),
        .S_AXI_WVALID    (S_AXI_WVALID),
        .S_AXI_WREADY    (S_AXI_WREADY),
        .S_AXI_BRESP     (S_AXI_BRESP),
        .S_AXI_BVALID    (S_AXI_BVALID),
        .S_AXI_BREADY    (S_AXI_BREADY),
        .S_AXI_ARADDR    (S_AXI_ARADDR),
        .S_AXI_ARPROT    (S_AXI_ARPROT),
        .S_AXI_ARVALID   (S_AXI_ARVALID),
        .S_AXI_ARREADY   (S_AXI_ARREADY),
        .S_AXI_RDATA     (S_AXI_RDATA),
        .S_AXI_RRESP     (S_AXI_RRESP),
        .S_AXI_RVALID    (S_AXI_RVALID),
        .S_AXI_RREADY    (S_AXI_RREADY)
    );

    // 100 MHz Clock
    initial begin
        S_AXI_ACLK = 1'b0;
        forever #5 S_AXI_ACLK = ~S_AXI_ACLK;
    end

    // -------------------------------------------------------------------------
    // CLEAR_ALL Pulse Monitor
    // -------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            clear_pulse_count    = 0;
            clear_width_error    = 0;
            clear_pulse_previous = 1'b0;
        end
        else begin
            if (dut.clear_all_pulse) begin
                clear_pulse_count = clear_pulse_count + 1;
                if (clear_pulse_previous)
                    clear_width_error = 1;
            end
            clear_pulse_previous = dut.clear_all_pulse;
        end
    end

    // CLEAR_ALL이 적용된 바로 그 Clock 뒤 Counter/Timeout이 Clear되는지 확인
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN && dut.clear_all_pulse) begin
            #1;
            if ((dut.last_count0 !== 32'd0) ||
                (dut.last_count1 !== 32'd0) ||
                (dut.last_count2 !== 32'd0) ||
                (timeout !== 3'b000)) begin
                clear_effect_error = 1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Utility Tasks
    // -------------------------------------------------------------------------
    task wait_clocks;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1)
                @(posedge S_AXI_ACLK);
            #1;
        end
    endtask

    task check_word;
        input [31:0] actual;
        input [31:0] expected;
        input [8*100-1:0] test_name;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s | actual=%0d(0x%08h) expected=%0d(0x%08h) @ %0t",
                         test_name, actual, actual, expected, expected, $time);
                error_count = error_count + 1;
            end
            else begin
                $display("[PASS] %0s @ %0t", test_name, $time);
            end
        end
    endtask

    task check_vec3;
        input [2:0] actual;
        input [2:0] expected;
        input [8*100-1:0] test_name;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s | actual=%03b expected=%03b @ %0t",
                         test_name, actual, expected, $time);
                error_count = error_count + 1;
            end
            else begin
                $display("[PASS] %0s @ %0t", test_name, $time);
            end
        end
    endtask

    task check_bit;
        input actual;
        input expected;
        input [8*100-1:0] test_name;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s | actual=%b expected=%b @ %0t",
                         test_name, actual, expected, $time);
                error_count = error_count + 1;
            end
            else begin
                $display("[PASS] %0s @ %0t", test_name, $time);
            end
        end
    endtask

    // AW와 W를 동시에 전송하는 일반 AXI Write
    task axi_write;
        input [ADDR_WIDTH-1:0] address;
        input [DATA_WIDTH-1:0] data;
        input [(DATA_WIDTH/8)-1:0] strobe;
        integer guard;
        begin
            @(negedge S_AXI_ACLK);
            S_AXI_AWADDR  = address;
            S_AXI_AWVALID = 1'b1;
            S_AXI_WDATA   = data;
            S_AXI_WSTRB   = strobe;
            S_AXI_WVALID  = 1'b1;
            S_AXI_BREADY  = 1'b0;

            guard = 0;
            while ((S_AXI_BVALID !== 1'b1) && (guard < 30)) begin
                @(posedge S_AXI_ACLK);
                #1;
                guard = guard + 1;
            end

            if (guard >= 30) begin
                $display("[FAIL] AXI Write response timeout: addr=0x%02h @ %0t",
                         address, $time);
                error_count = error_count + 1;
            end
            else if (S_AXI_BRESP !== 2'b00) begin
                $display("[FAIL] AXI Write BRESP is not OKAY: addr=0x%02h BRESP=%02b @ %0t",
                         address, S_AXI_BRESP, $time);
                error_count = error_count + 1;
            end

            @(negedge S_AXI_ACLK);
            S_AXI_AWVALID = 1'b0;
            S_AXI_WVALID  = 1'b0;
            S_AXI_BREADY  = 1'b1;

            @(posedge S_AXI_ACLK);
            #1;
            @(negedge S_AXI_ACLK);
            S_AXI_BREADY = 1'b0;
        end
    endtask

    // AW가 먼저 오고 W가 나중에 오는 경우
    task axi_write_aw_first;
        input [ADDR_WIDTH-1:0] address;
        input [DATA_WIDTH-1:0] data;
        integer guard;
        begin
            @(negedge S_AXI_ACLK);
            S_AXI_AWADDR  = address;
            S_AXI_AWVALID = 1'b1;
            @(posedge S_AXI_ACLK);
            #1;
            @(negedge S_AXI_ACLK);
            S_AXI_AWVALID = 1'b0;

            wait_clocks(2);

            @(negedge S_AXI_ACLK);
            S_AXI_WDATA  = data;
            S_AXI_WSTRB  = 4'b1111;
            S_AXI_WVALID = 1'b1;
            S_AXI_BREADY = 1'b0;

            guard = 0;
            while ((S_AXI_BVALID !== 1'b1) && (guard < 30)) begin
                @(posedge S_AXI_ACLK);
                #1;
                guard = guard + 1;
            end

            if (guard >= 30) begin
                $display("[FAIL] AXI AW-first response timeout: addr=0x%02h @ %0t",
                         address, $time);
                error_count = error_count + 1;
            end

            @(negedge S_AXI_ACLK);
            S_AXI_WVALID = 1'b0;
            S_AXI_BREADY = 1'b1;
            @(posedge S_AXI_ACLK);
            #1;
            @(negedge S_AXI_ACLK);
            S_AXI_BREADY = 1'b0;
        end
    endtask

    // W가 먼저 오고 AW가 나중에 오는 경우
    task axi_write_w_first;
        input [ADDR_WIDTH-1:0] address;
        input [DATA_WIDTH-1:0] data;
        integer guard;
        begin
            @(negedge S_AXI_ACLK);
            S_AXI_WDATA  = data;
            S_AXI_WSTRB  = 4'b1111;
            S_AXI_WVALID = 1'b1;
            @(posedge S_AXI_ACLK);
            #1;
            @(negedge S_AXI_ACLK);
            S_AXI_WVALID = 1'b0;

            wait_clocks(2);

            @(negedge S_AXI_ACLK);
            S_AXI_AWADDR  = address;
            S_AXI_AWVALID = 1'b1;
            S_AXI_BREADY  = 1'b0;

            guard = 0;
            while ((S_AXI_BVALID !== 1'b1) && (guard < 30)) begin
                @(posedge S_AXI_ACLK);
                #1;
                guard = guard + 1;
            end

            if (guard >= 30) begin
                $display("[FAIL] AXI W-first response timeout: addr=0x%02h @ %0t",
                         address, $time);
                error_count = error_count + 1;
            end

            @(negedge S_AXI_ACLK);
            S_AXI_AWVALID = 1'b0;
            S_AXI_BREADY  = 1'b1;
            @(posedge S_AXI_ACLK);
            #1;
            @(negedge S_AXI_ACLK);
            S_AXI_BREADY = 1'b0;
        end
    endtask

    task axi_read;
        input  [ADDR_WIDTH-1:0] address;
        output [DATA_WIDTH-1:0] data;
        integer guard;
        begin
            @(negedge S_AXI_ACLK);
            S_AXI_ARADDR  = address;
            S_AXI_ARVALID = 1'b1;
            S_AXI_RREADY  = 1'b0;

            guard = 0;
            while ((S_AXI_RVALID !== 1'b1) && (guard < 30)) begin
                @(posedge S_AXI_ACLK);
                #1;
                guard = guard + 1;
            end

            if (guard >= 30) begin
                $display("[FAIL] AXI Read response timeout: addr=0x%02h @ %0t",
                         address, $time);
                error_count = error_count + 1;
                data = 32'hXXXX_XXXX;
            end
            else begin
                data = S_AXI_RDATA;
                if (S_AXI_RRESP !== 2'b00) begin
                    $display("[FAIL] AXI Read RRESP is not OKAY: addr=0x%02h RRESP=%02b @ %0t",
                             address, S_AXI_RRESP, $time);
                    error_count = error_count + 1;
                end
            end

            @(negedge S_AXI_ACLK);
            S_AXI_ARVALID = 1'b0;
            S_AXI_RREADY  = 1'b1;
            @(posedge S_AXI_ACLK);
            #1;
            @(negedge S_AXI_ACLK);
            S_AXI_RREADY = 1'b0;
        end
    endtask

    task send_all_heartbeats;
        begin
            @(negedge S_AXI_ACLK);
            heartbeat_async = 3'b111;
            repeat (3) @(negedge S_AXI_ACLK);
            heartbeat_async = 3'b000;
        end
    endtask

    task wait_timeout_value;
        input [2:0] expected;
        input integer max_cycles;
        input [8*100-1:0] test_name;
        integer count;
        begin
            count = 0;
            while ((timeout !== expected) && (count < max_cycles)) begin
                @(posedge S_AXI_ACLK);
                #1;
                count = count + 1;
            end

            if (timeout !== expected) begin
                $display("[FAIL] %0s | timeout=%03b expected=%03b @ %0t",
                         test_name, timeout, expected, $time);
                error_count = error_count + 1;
            end
            else begin
                $display("[PASS] %0s @ %0t", test_name, $time);
            end
        end
    endtask

    task wait_irq_value;
        input expected;
        input integer max_cycles;
        input [8*100-1:0] test_name;
        integer count;
        begin
            count = 0;
            while ((irq !== expected) && (count < max_cycles)) begin
                @(posedge S_AXI_ACLK);
                #1;
                count = count + 1;
            end

            if (irq !== expected) begin
                $display("[FAIL] %0s | irq=%b expected=%b @ %0t",
                         test_name, irq, expected, $time);
                error_count = error_count + 1;
            end
            else begin
                $display("[PASS] %0s @ %0t", test_name, $time);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        heartbeat_async  = 3'b000;
        S_AXI_ARESETN    = 1'b0;
        S_AXI_AWADDR     = {ADDR_WIDTH{1'b0}};
        S_AXI_AWPROT     = 3'b000;
        S_AXI_AWVALID    = 1'b0;
        S_AXI_WDATA      = {DATA_WIDTH{1'b0}};
        S_AXI_WSTRB      = {(DATA_WIDTH/8){1'b0}};
        S_AXI_WVALID     = 1'b0;
        S_AXI_BREADY     = 1'b0;
        S_AXI_ARADDR     = {ADDR_WIDTH{1'b0}};
        S_AXI_ARPROT     = 3'b000;
        S_AXI_ARVALID    = 1'b0;
        S_AXI_RREADY     = 1'b0;

        error_count       = 0;
        clear_pulse_count = 0;
        clear_width_error = 0;
        clear_effect_error = 0;
        clear_pulse_previous = 1'b0;
        read_value = 32'd0;
        before_clear_count = 0;

        repeat (5) @(posedge S_AXI_ACLK);
        @(negedge S_AXI_ACLK);
        S_AXI_ARESETN = 1'b1;
        wait_clocks(2);

        // ---------------------------------------------------------------------
        $display("\n[AXI TEST 1] Reset default registers and safe outputs");
        axi_read(ADDR_CTRL, read_value);
        check_word(read_value, 32'h0000_0000, "Reset CTRL=0");
        axi_read(ADDR_TIMEOUT0, read_value);
        check_word(read_value, 32'h0000_0000, "Reset TIMEOUT0=0");
        axi_read(ADDR_TIMEOUT1, read_value);
        check_word(read_value, 32'h0000_0000, "Reset TIMEOUT1=0");
        axi_read(ADDR_TIMEOUT2, read_value);
        check_word(read_value, 32'h0000_0000, "Reset TIMEOUT2=0");
        axi_read(ADDR_IRQ_EN, read_value);
        check_word(read_value, 32'h0000_0000, "Reset IRQ_EN=0");
        axi_read(ADDR_IRQ_STATUS, read_value);
        check_word(read_value, 32'h0000_0000, "Reset IRQ_STATUS=0");
        axi_read(ADDR_STATUS, read_value);
        check_word(read_value, 32'h0000_0000, "Reset STATUS safe value");
        check_bit(irq, 1'b0, "Reset IRQ is Low");

        // ---------------------------------------------------------------------
        $display("\n[AXI TEST 2] TIMEOUT Write/Read and independent AW/W channels");
        axi_write_aw_first(ADDR_TIMEOUT0, 32'd100);
        axi_write_w_first(ADDR_TIMEOUT1, 32'd120);
        axi_write(ADDR_TIMEOUT2, 32'd140, 4'b1111);

        axi_read(ADDR_TIMEOUT0, read_value);
        check_word(read_value, 32'd100, "AW-first TIMEOUT0 Write/Read");
        axi_read(ADDR_TIMEOUT1, read_value);
        check_word(read_value, 32'd120, "W-first TIMEOUT1 Write/Read");
        axi_read(ADDR_TIMEOUT2, read_value);
        check_word(read_value, 32'd140, "Simultaneous AW/W TIMEOUT2 Write/Read");

        // ---------------------------------------------------------------------
        $display("\n[AXI TEST 3] Byte strobe write");
        axi_write(ADDR_TIMEOUT2, 32'h1122_3344, 4'b1111);
        axi_write(ADDR_TIMEOUT2, 32'h0000_0007, 4'b0001);
        axi_read(ADDR_TIMEOUT2, read_value);
        check_word(read_value, 32'h1122_3307, "WSTRB modifies only selected byte");
        axi_write(ADDR_TIMEOUT2, 32'd140, 4'b1111);

        // ---------------------------------------------------------------------
        $display("\n[AXI TEST 4] CTRL ENABLE and AUTO_RECOVER");
        axi_write(ADDR_CTRL, 32'h0000_0005, 4'b1111);
        axi_read(ADDR_CTRL, read_value);
        check_word(read_value, 32'h0000_0005, "CTRL stores ENABLE and AUTO_RECOVER");
        axi_read(ADDR_STATUS, read_value);
        check_word(read_value, 32'h0000_0007, "Enabled devices are Alive before timeout");

        // ---------------------------------------------------------------------
        $display("\n[AXI TEST 5] STATUS and LAST_COUNT are Read-only");
        axi_write(ADDR_CTRL, 32'h0000_0000, 4'b1111);
        axi_write(ADDR_STATUS, 32'hDEAD_BEEF, 4'b1111);
        axi_write(ADDR_LAST_COUNT0, 32'h1111_1111, 4'b1111);
        axi_write(ADDR_LAST_COUNT1, 32'h2222_2222, 4'b1111);
        axi_write(ADDR_LAST_COUNT2, 32'h3333_3333, 4'b1111);
        axi_read(ADDR_STATUS, read_value);
        check_word(read_value, 32'h0000_0000, "Write to STATUS is ignored");
        axi_read(ADDR_LAST_COUNT0, read_value);
        check_word(read_value, 32'h0000_0000, "Write to LAST_COUNT0 is ignored");
        axi_read(ADDR_LAST_COUNT1, read_value);
        check_word(read_value, 32'h0000_0000, "Write to LAST_COUNT1 is ignored");
        axi_read(ADDR_LAST_COUNT2, read_value);
        check_word(read_value, 32'h0000_0000, "Write to LAST_COUNT2 is ignored");

        // ---------------------------------------------------------------------
        $display("\n[AXI TEST 6] CLEAR_ALL W1P and CTRL bit1 non-storage");
        axi_write(ADDR_CTRL, 32'h0000_0005, 4'b1111);
        wait_clocks(6);
        before_clear_count = clear_pulse_count;
        axi_write(ADDR_CTRL, 32'h0000_0007, 4'b1111);
        axi_read(ADDR_CTRL, read_value);
        check_word(read_value, 32'h0000_0005, "CTRL CLEAR_ALL bit is not stored");
        check_word(clear_pulse_count, before_clear_count + 1,
                   "CLEAR_ALL generates exactly one pulse");
        check_bit(clear_width_error, 1'b0,
                  "CLEAR_ALL pulse width is one clock");
        check_bit(clear_effect_error, 1'b0,
                  "CLEAR_ALL clears counters and timeout at pulse clock");

        // ---------------------------------------------------------------------
        $display("\n[AXI TEST 7] IRQ_EN Write/Read");
        axi_write(ADDR_IRQ_EN, 32'h0000_0007, 4'b1111);
        axi_read(ADDR_IRQ_EN, read_value);
        check_word(read_value, 32'h0000_0007, "IRQ_EN[2:0] Write/Read");
        check_bit(irq, 1'b0, "IRQ remains Low without pending status");

        // ---------------------------------------------------------------------
        $display("\n[AXI TEST 8] Timeout event, IRQ_STATUS latch and W1C");
        axi_write(ADDR_CTRL, 32'h0000_0000, 4'b1111);
        axi_write(ADDR_TIMEOUT0, 32'd8,   4'b1111);
        axi_write(ADDR_TIMEOUT1, 32'd100, 4'b1111);
        axi_write(ADDR_TIMEOUT2, 32'd150, 4'b1111);
        axi_write(ADDR_IRQ_STATUS, 32'h0000_0007, 4'b1111);
        axi_write(ADDR_CTRL, 32'h0000_0001, 4'b1111);

        wait_timeout_value(3'b001, 30, "Device0 reaches timeout through AXI setting");
        wait_irq_value(1'b1, 5, "Timeout pending drives Level IRQ High");

        axi_read(ADDR_STATUS, read_value);
        check_word(read_value, 32'h0000_0106,
                   "STATUS packs Alive=110 and Timeout=001");
        axi_read(ADDR_IRQ_STATUS, read_value);
        check_word(read_value, 32'h0000_0001,
                   "Device0 event is latched in IRQ_STATUS");

        axi_write(ADDR_IRQ_STATUS, 32'h0000_0001, 4'b1111);
        axi_read(ADDR_IRQ_STATUS, read_value);
        check_word(read_value, 32'h0000_0000,
                   "W1C clears selected IRQ pending bit");
        check_vec3(timeout, 3'b001,
                   "IRQ_STATUS W1C does not clear Timeout state");
        check_bit(irq, 1'b0,
                  "IRQ goes Low after pending W1C");

        // ---------------------------------------------------------------------
        $display("\n[AXI TEST 9] CLEAR_ALL does not clear IRQ_STATUS");
        // 기존 Timeout을 Disable/Clear한 후 다시 Event 생성
        axi_write(ADDR_CTRL, 32'h0000_0002, 4'b1111);
        axi_write(ADDR_CTRL, 32'h0000_0001, 4'b1111);
        wait_timeout_value(3'b001, 30, "Device0 timeout is generated again");
        wait_irq_value(1'b1, 5, "IRQ_STATUS is set again");

        before_clear_count = clear_pulse_count;
        // ENABLE=0과 CLEAR_ALL을 함께 Write하여 재-Timeout을 막는다.
        axi_write(ADDR_CTRL, 32'h0000_0002, 4'b1111);
        check_word(clear_pulse_count, before_clear_count + 1,
                   "Second CLEAR_ALL also generates one pulse");
        check_vec3(timeout, 3'b000,
                   "CLEAR_ALL/Disable clears Timeout state");
        axi_read(ADDR_IRQ_STATUS, read_value);
        check_word(read_value, 32'h0000_0001,
                   "CLEAR_ALL leaves IRQ_STATUS pending unchanged");
        check_bit(irq, 1'b1,
                  "IRQ remains High while pending is uncleared");
        axi_write(ADDR_IRQ_STATUS, 32'h0000_0001, 4'b1111);
        check_bit(irq, 1'b0,
                  "W1C separately clears IRQ after CLEAR_ALL");

        // ---------------------------------------------------------------------
        $display("\n[AXI TEST 10] Three simultaneous pending bits and partial W1C");
        axi_write(ADDR_TIMEOUT0, 32'd6, 4'b1111);
        axi_write(ADDR_TIMEOUT1, 32'd6, 4'b1111);
        axi_write(ADDR_TIMEOUT2, 32'd6, 4'b1111);
        axi_write(ADDR_IRQ_STATUS, 32'h0000_0007, 4'b1111);
        axi_write(ADDR_IRQ_EN, 32'h0000_0007, 4'b1111);
        axi_write(ADDR_CTRL, 32'h0000_0001, 4'b1111);

        wait_timeout_value(3'b111, 30, "All devices time out simultaneously");
        wait_irq_value(1'b1, 5, "Simultaneous pending bits drive IRQ High");
        axi_read(ADDR_IRQ_STATUS, read_value);
        check_word(read_value, 32'h0000_0007,
                   "All timeout events latch IRQ_STATUS=111");

        // Timeout 상태를 Clear하지만 Pending은 유지
        axi_write(ADDR_CTRL, 32'h0000_0002, 4'b1111);
        check_vec3(timeout, 3'b000,
                   "CLEAR_ALL removes simultaneous Timeout states");
        axi_read(ADDR_IRQ_STATUS, read_value);
        check_word(read_value, 32'h0000_0007,
                   "Pending 111 remains after CLEAR_ALL");

        axi_write(ADDR_IRQ_STATUS, 32'h0000_0002, 4'b1111);
        axi_read(ADDR_IRQ_STATUS, read_value);
        check_word(read_value, 32'h0000_0005,
                   "Partial W1C clears only Device1 pending bit");
        check_bit(irq, 1'b1,
                  "IRQ remains High while Device0/2 pending remain");

        axi_write(ADDR_IRQ_STATUS, 32'h0000_0001, 4'b1111);
        axi_read(ADDR_IRQ_STATUS, read_value);
        check_word(read_value, 32'h0000_0004,
                   "Partial W1C leaves only Device2 pending");

        // Pending bit2가 남아 있어도 IRQ_EN[2]=0이면 irq는 Low
        axi_write(ADDR_IRQ_EN, 32'h0000_0003, 4'b1111);
        check_bit(irq, 1'b0,
                  "IRQ_EN masks the remaining Device2 pending bit");
        axi_read(ADDR_IRQ_STATUS, read_value);
        check_word(read_value, 32'h0000_0004,
                   "IRQ_EN mask does not erase IRQ_STATUS");

        axi_write(ADDR_IRQ_EN, 32'h0000_0007, 4'b1111);
        check_bit(irq, 1'b1,
                  "Re-enabling Device2 IRQ raises Level IRQ again");
        axi_write(ADDR_IRQ_STATUS, 32'h0000_0004, 4'b1111);
        axi_read(ADDR_IRQ_STATUS, read_value);
        check_word(read_value, 32'h0000_0000,
                   "Final W1C clears all pending bits");
        check_bit(irq, 1'b0,
                  "IRQ is Low after all pending bits are clear");

        // ---------------------------------------------------------------------
        $display("\n[AXI TEST 11] AUTO_RECOVER controlled through CTRL bit2");
        axi_write(ADDR_TIMEOUT0, 32'd4, 4'b1111);
        axi_write(ADDR_TIMEOUT1, 32'd4, 4'b1111);
        axi_write(ADDR_TIMEOUT2, 32'd4, 4'b1111);
        axi_write(ADDR_IRQ_STATUS, 32'h0000_0007, 4'b1111);
        axi_write(ADDR_CTRL, 32'h0000_0001, 4'b1111); // ENABLE=1, AUTO=0
        wait_timeout_value(3'b111, 30, "All devices time out with AUTO_RECOVER=0");

        // Timeout은 Latch된 상태로 두고 재발 방지를 위해 설정값을 크게 변경
        axi_write(ADDR_TIMEOUT0, 32'd100, 4'b1111);
        axi_write(ADDR_TIMEOUT1, 32'd100, 4'b1111);
        axi_write(ADDR_TIMEOUT2, 32'd100, 4'b1111);

        send_all_heartbeats();
        wait_clocks(4);
        check_vec3(timeout, 3'b111,
                   "AUTO_RECOVER=0 keeps Timeout after heartbeat");
        check_vec3(alive, 3'b000,
                   "Devices remain not alive with AUTO_RECOVER=0");

        axi_write(ADDR_CTRL, 32'h0000_0005, 4'b1111); // ENABLE=1, AUTO=1
        send_all_heartbeats();
        wait_timeout_value(3'b000, 10,
                           "AUTO_RECOVER=1 clears Timeout after heartbeat");
        check_vec3(alive, 3'b111,
                   "All devices become Alive after AXI auto recovery");
        axi_read(ADDR_CTRL, read_value);
        check_word(read_value, 32'h0000_0005,
                   "CTRL Read-back confirms AUTO_RECOVER=1");

        // ---------------------------------------------------------------------
        $display("\n[AXI TEST 12] Final global disable safe outputs");
        axi_write(ADDR_CTRL, 32'h0000_0000, 4'b1111);
        wait_clocks(1);
        check_vec3(alive, 3'b000, "Global disable forces Alive=000");
        check_vec3(timeout, 3'b000, "Global disable clears Timeout=000");
        axi_read(ADDR_STATUS, read_value);
        check_word(read_value, 32'h0000_0000,
                   "STATUS returns safe value after disable");

        // ---------------------------------------------------------------------
        if (error_count == 0) begin
            $display("\n====================================================");
            $display(" ALL HEARTBEAT AXI4-LITE TESTS PASSED");
            $display("====================================================\n");
        end
        else begin
            $display("\n====================================================");
            $display(" AXI TEST FAILED: %0d error(s)", error_count);
            $display("====================================================\n");
        end

        $finish;
    end

endmodule