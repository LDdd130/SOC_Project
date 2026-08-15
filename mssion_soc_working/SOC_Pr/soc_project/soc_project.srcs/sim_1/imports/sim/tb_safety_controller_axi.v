`timescale 1ns / 1ps
`default_nettype none

/*
 * tb_safety_controller_axi
 *
 * Safety Controller AXI4-Lite Wrapper 테스트벤치
 *
 * 검증 항목
 *   1. AXI Reset 후 레지스터 및 출력 초기값
 *   2. AXI AW/W 동시, AW 우선, W 우선 전달
 *   3. RW 레지스터와 WSTRB Byte Write
 *   4. Read-only 및 미정의 주소 처리
 *   5. Core 상태/출력/타이머의 AXI Read 반영
 *   6. RECOVERY_COUNT 설정값의 Core 적용
 *   7. IRQ Enable, Pending, W1C, Set 우선 정책
 *   8. MANUAL_RESET W1P 및 SAFE_MODE 복구
 *   9. Disable 및 fault_valid 안전 출력
 *
 * MEMBER C 필수 Testbench 대응
 *   - 필수 항목 25: IRQ_STATUS W1C
 *   - W1C의 WSTRB/Write-0 처리, IRQ Level 출력,
 *     State Change Event와 W1C 동시 발생 시 Event Set 우선까지 검증
 */
module tb_safety_controller_axi;

    localparam integer AXI_DATA_WIDTH = 32;
    localparam integer AXI_ADDR_WIDTH = 5;

    // 상태값
    localparam [1:0] ST_NORMAL    = 2'b00;
    localparam [1:0] ST_WARNING   = 2'b01;
    localparam [1:0] ST_DEGRADED  = 2'b10;
    localparam [1:0] ST_SAFE_MODE = 2'b11;

    // 레지스터 주소
    localparam [AXI_ADDR_WIDTH-1:0] ADDR_CTRL           = 5'h00;
    localparam [AXI_ADDR_WIDTH-1:0] ADDR_SYSTEM_STATE   = 5'h04;
    localparam [AXI_ADDR_WIDTH-1:0] ADDR_OUTPUT_ENABLE  = 5'h08;
    localparam [AXI_ADDR_WIDTH-1:0] ADDR_DEGRADE_MASK   = 5'h0C;
    localparam [AXI_ADDR_WIDTH-1:0] ADDR_RECOVERY_COUNT = 5'h10;
    localparam [AXI_ADDR_WIDTH-1:0] ADDR_STATE_TIMER    = 5'h14;
    localparam [AXI_ADDR_WIDTH-1:0] ADDR_IRQ_EN         = 5'h18;
    localparam [AXI_ADDR_WIDTH-1:0] ADDR_IRQ_STATUS     = 5'h1C;

    // AXI Write 전달 순서
    localparam integer ORDER_SAME     = 0;
    localparam integer ORDER_AW_FIRST = 1;
    localparam integer ORDER_W_FIRST  = 2;

    reg                              S_AXI_ACLK;
    reg                              S_AXI_ARESETN;

    reg  [AXI_ADDR_WIDTH-1:0]        S_AXI_AWADDR;
    reg                              S_AXI_AWVALID;
    wire                             S_AXI_AWREADY;

    reg  [AXI_DATA_WIDTH-1:0]        S_AXI_WDATA;
    reg  [(AXI_DATA_WIDTH/8)-1:0]    S_AXI_WSTRB;
    reg                              S_AXI_WVALID;
    wire                             S_AXI_WREADY;

    wire [1:0]                       S_AXI_BRESP;
    wire                             S_AXI_BVALID;
    reg                              S_AXI_BREADY;

    reg  [AXI_ADDR_WIDTH-1:0]        S_AXI_ARADDR;
    reg                              S_AXI_ARVALID;
    wire                             S_AXI_ARREADY;

    wire [AXI_DATA_WIDTH-1:0]        S_AXI_RDATA;
    wire [1:0]                       S_AXI_RRESP;
    wire                             S_AXI_RVALID;
    reg                              S_AXI_RREADY;

    reg  [1:0]                       fault_level;
    reg  [1:0]                       fault_device;
    reg  [7:0]                       fault_code;
    reg                              fault_valid;
    reg                              eval_tick;

    wire [1:0]                       system_state;
    wire [2:0]                       output_enable;
    wire                             actuator_enable;
    wire                             control_valid;
    wire [31:0]                      state_timer;
    wire                             irq;

    integer test_count;
    integer error_count;
    integer protocol_error_count;
    integer write_transaction_count;
    integer read_transaction_count;
    integer aw_handshake_count;
    integer w_handshake_count;
    integer b_handshake_count;
    integer ar_handshake_count;
    integer r_handshake_count;
    reg [31:0] read_data;

    /*
     * AXI protocol monitor용 이전 주기 값
     *
     * VALID/READY는 상승 에지에서만 Handshake로 판정한다.
     * VALID가 1인데 READY가 0인 동안에는 VALID와 Payload가 유지되어야 한다.
     */
    reg                              prev_awvalid;
    reg                              prev_awready;
    reg  [AXI_ADDR_WIDTH-1:0]        prev_awaddr;
    reg                              prev_wvalid;
    reg                              prev_wready;
    reg  [AXI_DATA_WIDTH-1:0]        prev_wdata;
    reg  [(AXI_DATA_WIDTH/8)-1:0]    prev_wstrb;
    reg                              prev_bvalid;
    reg                              prev_bready;
    reg  [1:0]                       prev_bresp;
    reg                              prev_arvalid;
    reg                              prev_arready;
    reg  [AXI_ADDR_WIDTH-1:0]        prev_araddr;
    reg                              prev_rvalid;
    reg                              prev_rready;
    reg  [AXI_DATA_WIDTH-1:0]        prev_rdata;
    reg  [1:0]                       prev_rresp;

    safety_controller_axi #(
        .C_S_AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH (AXI_ADDR_WIDTH)
    ) dut (
        .S_AXI_ACLK       (S_AXI_ACLK),
        .S_AXI_ARESETN    (S_AXI_ARESETN),

        .S_AXI_AWADDR     (S_AXI_AWADDR),
        .S_AXI_AWVALID    (S_AXI_AWVALID),
        .S_AXI_AWREADY    (S_AXI_AWREADY),

        .S_AXI_WDATA      (S_AXI_WDATA),
        .S_AXI_WSTRB      (S_AXI_WSTRB),
        .S_AXI_WVALID     (S_AXI_WVALID),
        .S_AXI_WREADY     (S_AXI_WREADY),

        .S_AXI_BRESP      (S_AXI_BRESP),
        .S_AXI_BVALID     (S_AXI_BVALID),
        .S_AXI_BREADY     (S_AXI_BREADY),

        .S_AXI_ARADDR     (S_AXI_ARADDR),
        .S_AXI_ARVALID    (S_AXI_ARVALID),
        .S_AXI_ARREADY    (S_AXI_ARREADY),

        .S_AXI_RDATA      (S_AXI_RDATA),
        .S_AXI_RRESP      (S_AXI_RRESP),
        .S_AXI_RVALID     (S_AXI_RVALID),
        .S_AXI_RREADY     (S_AXI_RREADY),

        .fault_level      (fault_level),
        .fault_device     (fault_device),
        .fault_code       (fault_code),
        .fault_valid      (fault_valid),
        .eval_tick        (eval_tick),

        .system_state     (system_state),
        .output_enable    (output_enable),
        .actuator_enable  (actuator_enable),
        .control_valid    (control_valid),
        .state_timer      (state_timer),
        .irq              (irq)
    );

    // 100 MHz AXI Clock
    always #5 S_AXI_ACLK = ~S_AXI_ACLK;

    /*
     * AXI4-Lite Protocol Monitor
     *
     * 이 Monitor는 파형을 눈으로만 확인하지 않고 아래 위반을 자동 검출한다.
     *   - AWVALID/WVALID/ARVALID이 READY 전 먼저 내려가는 경우
     *   - BVALID/RVALID이 READY 전 먼저 내려가는 경우
     *   - Stall 중 주소/데이터/응답 Payload가 바뀌는 경우
     *   - 각 채널의 상승 에지 Handshake 횟수
     */
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            protocol_error_count <= 0;
            aw_handshake_count   <= 0;
            w_handshake_count    <= 0;
            b_handshake_count    <= 0;
            ar_handshake_count   <= 0;
            r_handshake_count    <= 0;

            prev_awvalid <= 1'b0;
            prev_awready <= 1'b0;
            prev_awaddr  <= {AXI_ADDR_WIDTH{1'b0}};
            prev_wvalid  <= 1'b0;
            prev_wready  <= 1'b0;
            prev_wdata   <= {AXI_DATA_WIDTH{1'b0}};
            prev_wstrb   <= {(AXI_DATA_WIDTH/8){1'b0}};
            prev_bvalid  <= 1'b0;
            prev_bready  <= 1'b0;
            prev_bresp   <= 2'b00;
            prev_arvalid <= 1'b0;
            prev_arready <= 1'b0;
            prev_araddr  <= {AXI_ADDR_WIDTH{1'b0}};
            prev_rvalid  <= 1'b0;
            prev_rready  <= 1'b0;
            prev_rdata   <= {AXI_DATA_WIDTH{1'b0}};
            prev_rresp   <= 2'b00;
        end
        else begin
            // 상승 에지에서 VALID와 READY가 모두 1일 때만 Handshake이다.
            if (S_AXI_AWVALID && S_AXI_AWREADY)
                aw_handshake_count <= aw_handshake_count + 1;
            if (S_AXI_WVALID && S_AXI_WREADY)
                w_handshake_count <= w_handshake_count + 1;
            if (S_AXI_BVALID && S_AXI_BREADY)
                b_handshake_count <= b_handshake_count + 1;
            if (S_AXI_ARVALID && S_AXI_ARREADY)
                ar_handshake_count <= ar_handshake_count + 1;
            if (S_AXI_RVALID && S_AXI_RREADY)
                r_handshake_count <= r_handshake_count + 1;

            // Master 입력 채널 VALID/Payload 유지 검사
            if (prev_awvalid && !prev_awready) begin
                if (!S_AXI_AWVALID || (S_AXI_AWADDR !== prev_awaddr)) begin
                    protocol_error_count <= protocol_error_count + 1;
                    $display("[AXI PROTOCOL FAIL] AW 채널 Stall 중 VALID/ADDR 변경, 시간=%0t", $time);
                end
            end

            if (prev_wvalid && !prev_wready) begin
                if (!S_AXI_WVALID ||
                    (S_AXI_WDATA !== prev_wdata) ||
                    (S_AXI_WSTRB !== prev_wstrb)) begin
                    protocol_error_count <= protocol_error_count + 1;
                    $display("[AXI PROTOCOL FAIL] W 채널 Stall 중 VALID/DATA/STRB 변경, 시간=%0t", $time);
                end
            end

            if (prev_arvalid && !prev_arready) begin
                if (!S_AXI_ARVALID || (S_AXI_ARADDR !== prev_araddr)) begin
                    protocol_error_count <= protocol_error_count + 1;
                    $display("[AXI PROTOCOL FAIL] AR 채널 Stall 중 VALID/ADDR 변경, 시간=%0t", $time);
                end
            end

            // Slave 응답 채널 VALID/Payload 유지 검사
            if (prev_bvalid && !prev_bready) begin
                if (!S_AXI_BVALID || (S_AXI_BRESP !== prev_bresp)) begin
                    protocol_error_count <= protocol_error_count + 1;
                    $display("[AXI PROTOCOL FAIL] B 채널 Stall 중 BVALID/BRESP 변경, 시간=%0t", $time);
                end
            end

            if (prev_rvalid && !prev_rready) begin
                if (!S_AXI_RVALID ||
                    (S_AXI_RDATA !== prev_rdata) ||
                    (S_AXI_RRESP !== prev_rresp)) begin
                    protocol_error_count <= protocol_error_count + 1;
                    $display("[AXI PROTOCOL FAIL] R 채널 Stall 중 RVALID/RDATA/RRESP 변경, 시간=%0t", $time);
                end
            end

            prev_awvalid <= S_AXI_AWVALID;
            prev_awready <= S_AXI_AWREADY;
            prev_awaddr  <= S_AXI_AWADDR;
            prev_wvalid  <= S_AXI_WVALID;
            prev_wready  <= S_AXI_WREADY;
            prev_wdata   <= S_AXI_WDATA;
            prev_wstrb   <= S_AXI_WSTRB;
            prev_bvalid  <= S_AXI_BVALID;
            prev_bready  <= S_AXI_BREADY;
            prev_bresp   <= S_AXI_BRESP;
            prev_arvalid <= S_AXI_ARVALID;
            prev_arready <= S_AXI_ARREADY;
            prev_araddr  <= S_AXI_ARADDR;
            prev_rvalid  <= S_AXI_RVALID;
            prev_rready  <= S_AXI_RREADY;
            prev_rdata   <= S_AXI_RDATA;
            prev_rresp   <= S_AXI_RRESP;
        end
    end

    // AXI Handshake가 멈춘 경우 무한 대기를 방지하는 Watchdog
    initial begin
        #10000;
        $display("\n[TIMEOUT] 10 us 안에 AXI 테스트가 완료되지 않았습니다.");
        $finish;
    end

    /*
     * AXI Write Address 전송
     */
    task send_aw;
        input [AXI_ADDR_WIDTH-1:0] address;
        begin
            @(negedge S_AXI_ACLK);
            S_AXI_AWADDR  = address;
            S_AXI_AWVALID = 1'b1;

            while (S_AXI_AWREADY !== 1'b1)
                @(negedge S_AXI_ACLK);

            @(posedge S_AXI_ACLK);
            #1;

            @(negedge S_AXI_ACLK);
            S_AXI_AWVALID = 1'b0;
        end
    endtask

    /*
     * AXI Write Data 전송
     */
    task send_w;
        input [AXI_DATA_WIDTH-1:0]     data;
        input [(AXI_DATA_WIDTH/8)-1:0] strb;
        begin
            @(negedge S_AXI_ACLK);
            S_AXI_WDATA  = data;
            S_AXI_WSTRB  = strb;
            S_AXI_WVALID = 1'b1;

            while (S_AXI_WREADY !== 1'b1)
                @(negedge S_AXI_ACLK);

            @(posedge S_AXI_ACLK);
            #1;

            @(negedge S_AXI_ACLK);
            S_AXI_WVALID = 1'b0;
        end
    endtask

    /*
     * AXI Write Transaction
     *
     * order
     *   0 : AW와 W를 같은 클럭에 전달
     *   1 : AW를 먼저 전달
     *   2 : W를 먼저 전달
     */
    task axi_write;
        input [AXI_ADDR_WIDTH-1:0]     address;
        input [AXI_DATA_WIDTH-1:0]     data;
        input [(AXI_DATA_WIDTH/8)-1:0] strb;
        input integer                  order;
        begin
            write_transaction_count = write_transaction_count + 1;

            if (order == ORDER_SAME) begin
                @(negedge S_AXI_ACLK);
                S_AXI_AWADDR  = address;
                S_AXI_AWVALID = 1'b1;
                S_AXI_WDATA   = data;
                S_AXI_WSTRB   = strb;
                S_AXI_WVALID  = 1'b1;

                while ((S_AXI_AWREADY !== 1'b1) ||
                       (S_AXI_WREADY  !== 1'b1))
                    @(negedge S_AXI_ACLK);

                @(posedge S_AXI_ACLK);
                #1;

                @(negedge S_AXI_ACLK);
                S_AXI_AWVALID = 1'b0;
                S_AXI_WVALID  = 1'b0;
            end
            else if (order == ORDER_AW_FIRST) begin
                send_aw(address);
                @(posedge S_AXI_ACLK);
                send_w(data, strb);
            end
            else begin
                send_w(data, strb);
                @(posedge S_AXI_ACLK);
                send_aw(address);
            end

            // Write Response 대기
            while (S_AXI_BVALID !== 1'b1) begin
                @(posedge S_AXI_ACLK);
                #1;
            end

            if (S_AXI_BRESP !== 2'b00) begin
                error_count = error_count + 1;
                $display(
                    "[AXI ERROR] BRESP=%b, 주소=0x%02h, 시간=%0t",
                    S_AXI_BRESP,
                    address,
                    $time
                );
            end

            /*
             * BREADY를 일부러 2클럭 지연한다.
             * 이 동안 Slave는 BVALID/BRESP를 반드시 유지해야 한다.
             */
            repeat (2) begin
                @(posedge S_AXI_ACLK);
                #1;
                if ((S_AXI_BVALID !== 1'b1) ||
                    (S_AXI_BRESP !== 2'b00)) begin
                    error_count = error_count + 1;
                    $display(
                        "[AXI FAIL] BREADY=0 동안 BVALID/BRESP 유지 실패, 주소=0x%02h, 시간=%0t",
                        address,
                        $time
                    );
                end
            end

            // 다음 상승 에지에서 BVALID && BREADY Handshake를 만든다.
            @(negedge S_AXI_ACLK);
            S_AXI_BREADY = 1'b1;

            @(posedge S_AXI_ACLK);
            #1;

            if (!prev_bvalid || !prev_bready) begin
                error_count = error_count + 1;
                $display(
                    "[AXI FAIL] B 채널 상승 에지 Handshake 미성립, 주소=0x%02h, 시간=%0t",
                    address,
                    $time
                );
            end

            @(negedge S_AXI_ACLK);
            S_AXI_BREADY = 1'b0;
        end
    endtask

    /*
     * AXI Read Transaction
     */
    task axi_read;
        input  [AXI_ADDR_WIDTH-1:0] address;
        output [AXI_DATA_WIDTH-1:0] data;
        begin
            read_transaction_count = read_transaction_count + 1;

            @(negedge S_AXI_ACLK);
            S_AXI_ARADDR  = address;
            S_AXI_ARVALID = 1'b1;

            while (S_AXI_ARREADY !== 1'b1)
                @(negedge S_AXI_ACLK);

            @(posedge S_AXI_ACLK);
            #1;

            @(negedge S_AXI_ACLK);
            S_AXI_ARVALID = 1'b0;

            while (S_AXI_RVALID !== 1'b1) begin
                @(posedge S_AXI_ACLK);
                #1;
            end

            if (S_AXI_RRESP !== 2'b00) begin
                error_count = error_count + 1;
                $display(
                    "[AXI ERROR] RRESP=%b, 주소=0x%02h, 시간=%0t",
                    S_AXI_RRESP,
                    address,
                    $time
                );
            end

            /*
             * RREADY를 일부러 2클럭 지연한다.
             * 이 동안 Slave는 RVALID/RDATA/RRESP를 반드시 유지해야 한다.
             */
            data = S_AXI_RDATA;

            repeat (2) begin
                @(posedge S_AXI_ACLK);
                #1;
                if ((S_AXI_RVALID !== 1'b1) ||
                    (S_AXI_RDATA !== data) ||
                    (S_AXI_RRESP !== 2'b00)) begin
                    error_count = error_count + 1;
                    $display(
                        "[AXI FAIL] RREADY=0 동안 RVALID/RDATA/RRESP 유지 실패, 주소=0x%02h, 시간=%0t",
                        address,
                        $time
                    );
                end
            end

            // 다음 상승 에지에서 RVALID && RREADY Handshake를 만든다.
            @(negedge S_AXI_ACLK);
            S_AXI_RREADY = 1'b1;

            @(posedge S_AXI_ACLK);
            #1;

            if (!prev_rvalid || !prev_rready) begin
                error_count = error_count + 1;
                $display(
                    "[AXI FAIL] R 채널 상승 에지 Handshake 미성립, 주소=0x%02h, 시간=%0t",
                    address,
                    $time
                );
            end

            @(negedge S_AXI_ACLK);
            S_AXI_RREADY = 1'b0;
        end
    endtask

    // AXI Read 결과를 기대값과 비교한다.
    task check_axi_read;
        input [AXI_ADDR_WIDTH-1:0] address;
        input [31:0]               expected_value;
        begin
            axi_read(address, read_data);
            test_count = test_count + 1;

            if (read_data !== expected_value) begin
                error_count = error_count + 1;
                $display(
                    "[FAIL %0d] 주소=0x%02h, 기대값=0x%08h, 실제값=0x%08h, 시간=%0t",
                    test_count,
                    address,
                    expected_value,
                    read_data,
                    $time
                );
            end
            else begin
                $display(
                    "[PASS %0d] 주소=0x%02h, Read=0x%08h, 시간=%0t",
                    test_count,
                    address,
                    read_data,
                    $time
                );
            end
        end
    endtask

    // 상태값 비교
    task check_state;
        input [1:0] expected_state;
        begin
            test_count = test_count + 1;

            if (system_state !== expected_state) begin
                error_count = error_count + 1;
                $display(
                    "[FAIL %0d] 상태 기대값=%b, 실제값=%b, 시간=%0t",
                    test_count,
                    expected_state,
                    system_state,
                    $time
                );
            end
            else begin
                $display(
                    "[PASS %0d] 상태=%b, 시간=%0t",
                    test_count,
                    system_state,
                    $time
                );
            end
        end
    endtask

    // Core 출력값 비교
    task check_outputs;
        input [2:0] expected_output;
        input       expected_actuator;
        input       expected_valid;
        begin
            test_count = test_count + 1;

            if ((output_enable   !== expected_output)   ||
                (actuator_enable !== expected_actuator) ||
                (control_valid   !== expected_valid)) begin
                error_count = error_count + 1;
                $display(
                    "[FAIL %0d] 출력 기대값=%b/%b/%b, 실제값=%b/%b/%b, 시간=%0t",
                    test_count,
                    expected_output,
                    expected_actuator,
                    expected_valid,
                    output_enable,
                    actuator_enable,
                    control_valid,
                    $time
                );
            end
            else begin
                $display(
                    "[PASS %0d] 출력=%b/%b/%b, 시간=%0t",
                    test_count,
                    output_enable,
                    actuator_enable,
                    control_valid,
                    $time
                );
            end
        end
    endtask

    // 1비트 신호 비교
    task check_bit;
        input actual_value;
        input expected_value;
        begin
            test_count = test_count + 1;

            if (actual_value !== expected_value) begin
                error_count = error_count + 1;
                $display(
                    "[FAIL %0d] 1비트 기대값=%b, 실제값=%b, 시간=%0t",
                    test_count,
                    expected_value,
                    actual_value,
                    $time
                );
            end
            else begin
                $display(
                    "[PASS %0d] 1비트 신호=%b, 시간=%0t",
                    test_count,
                    actual_value,
                    $time
                );
            end
        end
    endtask

    // 32비트 값이 0이 아닌지 확인
    task check_nonzero;
        input [31:0] actual_value;
        begin
            test_count = test_count + 1;

            if ((actual_value === 32'd0) ||
                (^actual_value === 1'bx)) begin
                error_count = error_count + 1;
                $display(
                    "[FAIL %0d] 0이 아닌 값 기대, 실제값=0x%08h, 시간=%0t",
                    test_count,
                    actual_value,
                    $time
                );
            end
            else begin
                $display(
                    "[PASS %0d] 0이 아닌 값=0x%08h, 시간=%0t",
                    test_count,
                    actual_value,
                    $time
                );
            end
        end
    endtask

    // Fault를 변경하고 다음 클럭의 즉시 상태 전환을 기다린다.
    task apply_fault_immediate;
        input [1:0] level;
        input [1:0] device;
        begin
            @(negedge S_AXI_ACLK);
            fault_level  = level;
            fault_device = device;
            fault_valid  = 1'b1;
            eval_tick    = 1'b0;

            @(posedge S_AXI_ACLK);
            #1;
        end
    endtask

    // 복구 평가 Tick을 한 클럭 발생시킨다.
    task apply_eval_tick;
        input [1:0] level;
        begin
            @(negedge S_AXI_ACLK);
            fault_level = level;
            fault_valid = 1'b1;
            eval_tick   = 1'b1;

            @(posedge S_AXI_ACLK);
            #1;

            @(negedge S_AXI_ACLK);
            eval_tick = 1'b0;
        end
    endtask

    /*
     * 상태 변경과 IRQ_STATUS W1C Commit을 같은 클럭에 발생시킨다.
     * Event Set이 W1C보다 우선하는지 검증하기 위한 전용 Transaction이다.
     */
    task write_w1c_with_fault_event;
        input [1:0] level;
        input [1:0] device;
        begin
            write_transaction_count = write_transaction_count + 1;

            @(negedge S_AXI_ACLK);
            fault_level   = level;
            fault_device  = device;
            fault_valid   = 1'b1;
            eval_tick     = 1'b0;

            S_AXI_AWADDR  = ADDR_IRQ_STATUS;
            S_AXI_AWVALID = 1'b1;
            S_AXI_WDATA   = 32'h0000_0001;
            S_AXI_WSTRB   = 4'b0001;
            S_AXI_WVALID  = 1'b1;

            while ((S_AXI_AWREADY !== 1'b1) ||
                   (S_AXI_WREADY  !== 1'b1))
                @(negedge S_AXI_ACLK);

            // 이 클럭에서 Core 상태가 바뀌고 state_change_event가 생성된다.
            @(posedge S_AXI_ACLK);
            #1;

            @(negedge S_AXI_ACLK);
            S_AXI_AWVALID = 1'b0;
            S_AXI_WVALID  = 1'b0;

            /*
             * 다음 클럭에서 Write Commit과 IRQ Event Set이 동시에 평가된다.
             * RTL 정책에 따라 Event Set이 우선해 Pending은 1이어야 한다.
             */
            while (S_AXI_BVALID !== 1'b1) begin
                @(posedge S_AXI_ACLK);
                #1;
            end

            if (S_AXI_BRESP !== 2'b00) begin
                error_count = error_count + 1;
                $display(
                    "[AXI ERROR] 동시 이벤트 테스트 BRESP=%b, 시간=%0t",
                    S_AXI_BRESP,
                    $time
                );
            end

            @(negedge S_AXI_ACLK);
            S_AXI_BREADY = 1'b1;

            @(posedge S_AXI_ACLK);
            #1;

            @(negedge S_AXI_ACLK);
            S_AXI_BREADY = 1'b0;
        end
    endtask

    initial begin
        S_AXI_ACLK     = 1'b0;
        S_AXI_ARESETN  = 1'b0;

        S_AXI_AWADDR   = {AXI_ADDR_WIDTH{1'b0}};
        S_AXI_AWVALID  = 1'b0;
        S_AXI_WDATA    = {AXI_DATA_WIDTH{1'b0}};
        S_AXI_WSTRB    = {(AXI_DATA_WIDTH/8){1'b0}};
        S_AXI_WVALID   = 1'b0;
        S_AXI_BREADY   = 1'b0;

        S_AXI_ARADDR   = {AXI_ADDR_WIDTH{1'b0}};
        S_AXI_ARVALID  = 1'b0;
        S_AXI_RREADY   = 1'b0;

        fault_level    = 2'd0;
        fault_device   = 2'd0;
        fault_code     = 8'd0;
        fault_valid    = 1'b1;
        eval_tick      = 1'b0;

        test_count     = 0;
        error_count    = 0;
        protocol_error_count   = 0;
        write_transaction_count = 0;
        read_transaction_count  = 0;
        read_data      = 32'd0;

        // AXI Reset을 충분히 유지한다.
        repeat (4) @(posedge S_AXI_ACLK);

        @(negedge S_AXI_ACLK);
        S_AXI_ARESETN = 1'b1;

        @(posedge S_AXI_ACLK);
        #1;

        /*
         * T1: Reset 초기값
         */
        $display("\n[T1] AXI Reset 후 초기값");
        check_state(ST_NORMAL);
        check_outputs(3'b000, 1'b0, 1'b0);
        check_bit(irq, 1'b0);
        check_axi_read(ADDR_CTRL,           32'h0000_0000);
        check_axi_read(ADDR_DEGRADE_MASK,   32'h0000_0000);
        check_axi_read(ADDR_RECOVERY_COUNT, 32'h0000_0000);
        check_axi_read(ADDR_IRQ_EN,         32'h0000_0000);
        check_axi_read(ADDR_IRQ_STATUS,     32'h0000_0000);

        /*
         * T2: AXI Write 채널 독립성과 RW 레지스터
         */
        $display("\n[T2] AXI AW/W 전달 순서 및 RW 레지스터");

        // AW와 W 동시 전달
        axi_write(ADDR_CTRL, 32'h0000_0001, 4'b0001, ORDER_SAME);
        check_axi_read(ADDR_CTRL, 32'h0000_0001);
        check_outputs(3'b111, 1'b1, 1'b1);

        // AW를 먼저 전달
        axi_write(ADDR_DEGRADE_MASK, 32'h0000_0005, 4'b0001,
                  ORDER_AW_FIRST);
        check_axi_read(ADDR_DEGRADE_MASK, 32'h0000_0005);

        // W를 먼저 전달
        axi_write(ADDR_RECOVERY_COUNT, 32'h0000_ABCD, 4'b0011,
                  ORDER_W_FIRST);
        check_axi_read(ADDR_RECOVERY_COUNT, 32'h0000_ABCD);

        /*
         * T3: WSTRB Byte Write
         */
        $display("\n[T3] WSTRB Byte Write");

        // Low Byte만 변경: 0xABCD -> 0xAB55
        axi_write(ADDR_RECOVERY_COUNT, 32'h0000_0055, 4'b0001,
                  ORDER_SAME);
        check_axi_read(ADDR_RECOVERY_COUNT, 32'h0000_AB55);

        // High Byte만 변경: 0xAB55 -> 0x1255
        axi_write(ADDR_RECOVERY_COUNT, 32'h0000_1200, 4'b0010,
                  ORDER_SAME);
        check_axi_read(ADDR_RECOVERY_COUNT, 32'h0000_1255);

        // WSTRB=0이면 값 유지
        axi_write(ADDR_RECOVERY_COUNT, 32'h0000_FFFF, 4'b0000,
                  ORDER_SAME);
        check_axi_read(ADDR_RECOVERY_COUNT, 32'h0000_1255);

        // CTRL도 WSTRB=0이면 ENABLE 유지
        axi_write(ADDR_CTRL, 32'h0000_0000, 4'b0000, ORDER_SAME);
        check_axi_read(ADDR_CTRL, 32'h0000_0001);

        // 이후 복구 테스트에서 사용할 설정값 2
        axi_write(ADDR_RECOVERY_COUNT, 32'h0000_0002, 4'b0011,
                  ORDER_SAME);
        check_axi_read(ADDR_RECOVERY_COUNT, 32'h0000_0002);

        /*
         * T4: Read-only 및 미정의 주소
         */
        $display("\n[T4] Read-only 및 미정의 주소 처리");
        axi_write(ADDR_SYSTEM_STATE, 32'hFFFF_FFFF, 4'b1111,
                  ORDER_SAME);
        check_axi_read(ADDR_SYSTEM_STATE, 32'h0000_0000);
        check_axi_read(5'h1D, 32'h0000_0000);

        /*
         * T5: Core 상태/출력과 IRQ Pending 반영
         */
        $display("\n[T5] 상태/출력 Read 및 IRQ Pending");

        // fault_device=3이면 DEGRADE_MASK=101을 적용해 출력은 010
        apply_fault_immediate(2'd2, 2'd3);
        check_state(ST_DEGRADED);
        check_outputs(3'b010, 1'b1, 1'b1);

        // IRQ_STATUS는 state_change_event를 다음 클럭에 Pending으로 저장한다.
        @(posedge S_AXI_ACLK);
        #1;

        check_axi_read(ADDR_SYSTEM_STATE,  32'h0000_0002);
        check_axi_read(ADDR_OUTPUT_ENABLE, 32'h0000_0002);
        check_axi_read(ADDR_IRQ_STATUS,    32'h0000_0001);

        // IRQ가 Disable이면 Pending이 있어도 외부 IRQ는 Low
        check_bit(irq, 1'b0);

        // 상태 유지 시간이 AXI Read에 반영되는지 확인
        axi_read(ADDR_STATE_TIMER, read_data);
        check_nonzero(read_data);

        // IRQ Enable 후 이미 존재하는 Pending이 외부 IRQ로 전달됨
        axi_write(ADDR_IRQ_EN, 32'h0000_0001, 4'b0001, ORDER_SAME);
        check_axi_read(ADDR_IRQ_EN, 32'h0000_0001);
        check_bit(irq, 1'b1);

        /*
         * T6: IRQ_STATUS W1C
         */
        $display("\n[T6 / 필수항목 25] IRQ_STATUS W1C");

        // 0을 쓰면 Pending 유지
        axi_write(ADDR_IRQ_STATUS, 32'h0000_0000, 4'b0001,
                  ORDER_SAME);
        check_axi_read(ADDR_IRQ_STATUS, 32'h0000_0001);

        // WSTRB가 0이면 1을 써도 Pending 유지
        axi_write(ADDR_IRQ_STATUS, 32'h0000_0001, 4'b0000,
                  ORDER_SAME);
        check_axi_read(ADDR_IRQ_STATUS, 32'h0000_0001);

        // bit0에 1을 쓰면 Pending Clear
        axi_write(ADDR_IRQ_STATUS, 32'h0000_0001, 4'b0001,
                  ORDER_SAME);
        check_axi_read(ADDR_IRQ_STATUS, 32'h0000_0000);
        check_bit(irq, 1'b0);

        /*
         * T7: AXI RECOVERY_COUNT 설정값의 Core 적용
         */
        $display("\n[T7] RECOVERY_COUNT 설정값 적용");

        // DEGRADED에서 Level 1을 2회 확인하면 WARNING으로 복구
        apply_eval_tick(2'd1);
        check_state(ST_DEGRADED);

        apply_eval_tick(2'd1);
        check_state(ST_WARNING);

        // WARNING에서 Level 0을 2회 확인하면 NORMAL로 복구
        apply_eval_tick(2'd0);
        check_state(ST_WARNING);

        apply_eval_tick(2'd0);
        check_state(ST_NORMAL);

        // 복구 과정에서 발생한 IRQ Pending을 안정적으로 Clear
        repeat (2) @(posedge S_AXI_ACLK);
        axi_write(ADDR_IRQ_STATUS, 32'h0000_0001, 4'b0001,
                  ORDER_SAME);
        check_axi_read(ADDR_IRQ_STATUS, 32'h0000_0000);
        check_bit(irq, 1'b0);

        /*
         * T8: SAFE_MODE와 MANUAL_RESET W1P
         */
        $display("\n[T8] SAFE_MODE 및 MANUAL_RESET W1P");

        apply_fault_immediate(2'd3, 2'd0);
        check_state(ST_SAFE_MODE);
        check_outputs(3'b000, 1'b0, 1'b0);

        // Level 0과 eval_tick만으로는 SAFE_MODE 자동 복구 금지
        apply_eval_tick(2'd0);
        apply_eval_tick(2'd0);
        check_state(ST_SAFE_MODE);

        /*
         * CTRL bit1에 1을 쓰면 Manual Reset Pulse가 생성된다.
         * bit0도 1로 함께 써 ENABLE은 유지한다.
         */
        axi_write(ADDR_CTRL, 32'h0000_0003, 4'b0001, ORDER_SAME);
        check_state(ST_NORMAL);
        check_outputs(3'b111, 1'b1, 1'b1);

        // MANUAL_RESET은 W1P이므로 Read 시 bit1은 항상 0
        check_axi_read(ADDR_CTRL, 32'h0000_0001);
        check_bit(dut.manual_reset_pulse, 1'b0);

        // SAFE_MODE 진입/해제 상태 변경으로 IRQ가 발생해야 함
        check_bit(irq, 1'b1);

        /*
         * T9: Event Set과 W1C 동시 발생 시 Event Set 우선
         */
        $display("\n[T9] IRQ Event Set 우선 정책");

        // 앞선 상태 변경 이벤트가 모두 반영된 뒤 Pending Clear
        repeat (2) @(posedge S_AXI_ACLK);
        axi_write(ADDR_IRQ_STATUS, 32'h0000_0001, 4'b0001,
                  ORDER_SAME);
        check_axi_read(ADDR_IRQ_STATUS, 32'h0000_0000);

        /*
         * NORMAL->WARNING 상태 변경 이벤트와 W1C Commit을 같은 클럭에
         * 발생시킨다. Event Set 우선이므로 Pending은 1로 남아야 한다.
         */
        write_w1c_with_fault_event(2'd1, 2'd0);
        check_state(ST_WARNING);
        check_axi_read(ADDR_IRQ_STATUS, 32'h0000_0001);
        check_bit(irq, 1'b1);

        // 일반 W1C로 다시 Clear
        axi_write(ADDR_IRQ_STATUS, 32'h0000_0001, 4'b0001,
                  ORDER_SAME);
        check_axi_read(ADDR_IRQ_STATUS, 32'h0000_0000);
        check_bit(irq, 1'b0);

        /*
         * T10: Disable 정책
         */
        $display("\n[T10] CTRL.ENABLE Disable 정책");

        axi_write(ADDR_CTRL, 32'h0000_0000, 4'b0001, ORDER_SAME);
        check_state(ST_NORMAL);
        check_outputs(3'b000, 1'b0, 1'b0);
        check_axi_read(ADDR_CTRL, 32'h0000_0000);
        check_axi_read(ADDR_STATE_TIMER, 32'h0000_0000);

        /*
         * T11: 재활성화 및 fault_valid 안전 출력
         */
        $display("\n[T11] 재활성화 및 fault_valid 안전 출력");

        @(negedge S_AXI_ACLK);
        fault_level = 2'd0;
        fault_valid = 1'b1;

        axi_write(ADDR_CTRL, 32'h0000_0001, 4'b0001, ORDER_SAME);
        check_state(ST_NORMAL);
        check_outputs(3'b111, 1'b1, 1'b1);

        @(negedge S_AXI_ACLK);
        fault_valid = 1'b0;

        @(posedge S_AXI_ACLK);
        #1;

        check_state(ST_NORMAL);
        check_outputs(3'b000, 1'b0, 1'b0);
        check_axi_read(ADDR_OUTPUT_ENABLE, 32'h0000_0000);

        /*
         * 최종 결과
         */
        // 마지막 Handshake Counter의 NBA 갱신이 끝나도록 한 클럭 대기한다.
        @(posedge S_AXI_ACLK);
        #1;

        test_count = test_count + 1;
        if ((aw_handshake_count !== write_transaction_count) ||
            (w_handshake_count  !== write_transaction_count) ||
            (b_handshake_count  !== write_transaction_count)) begin
            error_count = error_count + 1;
            $display(
                "[FAIL %0d] AXI Write HS 횟수 AW/W/B=%0d/%0d/%0d, Transaction=%0d",
                test_count,
                aw_handshake_count,
                w_handshake_count,
                b_handshake_count,
                write_transaction_count
            );
        end
        else begin
            $display(
                "[PASS %0d] AXI Write HS 횟수 AW/W/B=%0d/%0d/%0d",
                test_count,
                aw_handshake_count,
                w_handshake_count,
                b_handshake_count
            );
        end

        test_count = test_count + 1;
        if ((ar_handshake_count !== read_transaction_count) ||
            (r_handshake_count  !== read_transaction_count)) begin
            error_count = error_count + 1;
            $display(
                "[FAIL %0d] AXI Read HS 횟수 AR/R=%0d/%0d, Transaction=%0d",
                test_count,
                ar_handshake_count,
                r_handshake_count,
                read_transaction_count
            );
        end
        else begin
            $display(
                "[PASS %0d] AXI Read HS 횟수 AR/R=%0d/%0d",
                test_count,
                ar_handshake_count,
                r_handshake_count
            );
        end

        test_count = test_count + 1;
        if (protocol_error_count != 0) begin
            error_count = error_count + protocol_error_count;
            $display(
                "[FAIL %0d] AXI Protocol Monitor 오류=%0d",
                test_count,
                protocol_error_count
            );
        end
        else begin
            $display(
                "[PASS %0d] AXI Protocol Monitor 오류 없음",
                test_count
            );
        end

        $display("\n========================================");

        if (error_count == 0) begin
            $display(
                "ALL TESTS PASSED: 총 %0d개 검증 통과",
                test_count
            );
        end
        else begin
            $display(
                "TEST FAILED: 총 %0d개 검증 중 %0d개 실패",
                test_count,
                error_count
            );
        end

        $display("========================================\n");

        #20;
        $finish;
    end

endmodule

`default_nettype wire
