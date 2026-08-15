`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 파일 : tb_fault_manager_axi.v
// 역할 : fault_manager_axi Self-checking Testbench
//        04 통합 체크리스트 3장의 AXI 항목을 미리 검증한다.
//          1) 모든 레지스터 Read/Write, Read-only Write 무시
//          2) W1P 가 정확히 1 Clock Pulse
//          3) W1C 가 지정 비트만 Clear
//          4) IRQ 가 Clear 전까지 High 유지 (Level 방식)
//          5) RESET_FAULT 는 활성 Fault 가 있으면 무시, 없으면 Count/Pending Clear
//          6) ENABLE=0 안전 출력
//
//        (2026-07-30 추가) AXI4-Lite 규격 준수 항목. src/fault_manager_axi.v 가
//        aw_pending / w_pending / wstrb_hold 로 재작성된 것을 실제로 검증한다.
//        이 항목들이 없으면 RTL 은 고쳐졌지만 검증은 공백인 상태가 된다.
//          7)  AW 먼저 도착 (W 지연)
//          8)  W 먼저 도착 (AW 지연)  <- 구 래퍼가 교착하던 케이스
//          9)  WSTRB : byte0 이 꺼진 Write 는 RW/W1P/W1C 모두 무시
//          10) BREADY/RREADY 지연 시 응답 유지, 응답 미완료 중 새 요청 차단
//          11) 백투백 연속 Write / 연속 Read 에서 요청 유실 없음
//        + AXI Protocol Monitor : Stall 중 VALID/Payload 변경 감시, Handshake 카운트
//
// eval_tick 은 이 IP 가 만들지 않는다. 공통 eval_tick_generator 를 흉내내어
// TB 가 1클럭 Pulse 를 넣는다 (00 문서 5.2).
//////////////////////////////////////////////////////////////////////////////////

module tb_fault_manager_axi;

    localparam ADDR_CTRL          = 6'h00,
               ADDR_FAULT_INPUT   = 6'h04,
               ADDR_CRITICAL_MASK = 6'h08,
               ADDR_PERSIST_LIMIT = 6'h0C,
               ADDR_FAULT_LEVEL   = 6'h10,
               ADDR_FAULT_DEVICE  = 6'h14,
               ADDR_FAULT_CODE    = 6'h18,
               ADDR_FAULT_COUNT   = 6'h1C,
               ADDR_IRQ_EN        = 6'h20,
               ADDR_IRQ_STATUS    = 6'h24,
               ADDR_ID            = 6'h2C;

    reg ACLK = 0, ARESETN = 0;
    always #5 ACLK = ~ACLK;

    reg  [5:0]  AWADDR = 0;  reg AWVALID = 0;  wire AWREADY;
    reg  [31:0] WDATA  = 0;  reg [3:0] WSTRB = 4'hF; reg WVALID = 0; wire WREADY;
    wire [1:0]  BRESP;       wire BVALID;      reg  BREADY = 0;
    reg  [5:0]  ARADDR = 0;  reg ARVALID = 0;  wire ARREADY;
    wire [31:0] RDATA;       wire [1:0] RRESP; wire RVALID; reg RREADY = 0;

    reg  [2:0] timeout = 3'b000, error_flag = 3'b000, critical_fault = 3'b000;
    wire [1:0] fault_level, fault_device;
    wire [7:0] fault_code;
    wire       fault_valid, irq;

    //--------------------------------------------------------------------------
    // 공통 eval_tick 모사 : tick_en=1 이면 10 클럭마다 1클럭 Pulse
    //--------------------------------------------------------------------------
    reg        tick_en   = 1'b0;
    reg  [7:0] tick_div  = 8'd0;
    reg        eval_tick = 1'b0;

    always @(posedge ACLK) begin
        eval_tick <= 1'b0;
        if (!ARESETN || !tick_en) tick_div <= 8'd0;
        else if (tick_div >= 8'd9) begin
            tick_div  <= 8'd0;
            eval_tick <= 1'b1;
        end
        else tick_div <= tick_div + 8'd1;
    end

    fault_manager_axi dut (
        .timeout(timeout), .error_flag(error_flag), .critical_fault(critical_fault),
        .eval_tick(eval_tick),
        .fault_level(fault_level), .fault_device(fault_device), .fault_code(fault_code),
        .fault_valid(fault_valid), .irq(irq),
        .S_AXI_ACLK(ACLK), .S_AXI_ARESETN(ARESETN),
        .S_AXI_AWADDR(AWADDR), .S_AXI_AWPROT(3'b000), .S_AXI_AWVALID(AWVALID),
        .S_AXI_AWREADY(AWREADY),
        .S_AXI_WDATA(WDATA), .S_AXI_WSTRB(WSTRB), .S_AXI_WVALID(WVALID),
        .S_AXI_WREADY(WREADY),
        .S_AXI_BRESP(BRESP), .S_AXI_BVALID(BVALID), .S_AXI_BREADY(BREADY),
        .S_AXI_ARADDR(ARADDR), .S_AXI_ARPROT(3'b000), .S_AXI_ARVALID(ARVALID),
        .S_AXI_ARREADY(ARREADY),
        .S_AXI_RDATA(RDATA), .S_AXI_RRESP(RRESP), .S_AXI_RVALID(RVALID),
        .S_AXI_RREADY(RREADY));

    integer errors = 0, checks = 0;
    integer i;
    reg [31:0] rd;

    // W1P 폭 감시 : reset_fault_pulse 가 1 인 연속 클럭 수를 센다
    integer pulse_len = 0, pulse_max = 0;
    always @(posedge ACLK) begin
        if (dut.reset_fault_pulse) pulse_len = pulse_len + 1;
        else begin
            if (pulse_len > pulse_max) pulse_max = pulse_len;
            pulse_len = 0;
        end
    end

    //--------------------------------------------------------------------------
    // AXI4-Lite BFM
    //--------------------------------------------------------------------------
    task axi_write(input [5:0] addr, input [31:0] data);
        begin
            @(negedge ACLK);
            AWADDR = addr; AWVALID = 1'b1;
            WDATA  = data; WSTRB = 4'hF; WVALID = 1'b1;
            BREADY = 1'b1;
            @(posedge ACLK);
            while (!(AWREADY && WREADY)) @(posedge ACLK);
            @(negedge ACLK);
            AWVALID = 1'b0; WVALID = 1'b0;
            while (!BVALID) @(posedge ACLK);
            @(negedge ACLK);
            BREADY = 1'b0;
        end
    endtask

    task axi_read(input [5:0] addr, output [31:0] data);
        begin
            @(negedge ACLK);
            ARADDR = addr; ARVALID = 1'b1; RREADY = 1'b1;
            @(posedge ACLK);
            while (!ARREADY) @(posedge ACLK);
            @(negedge ACLK);
            ARVALID = 1'b0;
            while (!RVALID) @(posedge ACLK);
            data = RDATA;
            @(negedge ACLK);
            RREADY = 1'b0;
        end
    endtask

    task check32(input [31:0] got, input [31:0] exp, input [8*120:1] name);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] %0s  got=0x%08h exp=0x%08h", name, got, exp);
            end
            else $display("  [PASS] %0s  (0x%08h)", name, got);
        end
    endtask

    task check_bit(input got, input exp, input [8*120:1] name);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] %0s  got=%b exp=%b", name, got, exp);
            end
            else $display("  [PASS] %0s  (%b)", name, got);
        end
    endtask

    task check_int_task(input integer got, input integer exp, input [8*120:1] name);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] %0s  got=%0d exp=%0d", name, got, exp);
            end
            else $display("  [PASS] %0s  (=%0d)", name, got);
        end
    endtask

    // 지속 Count 를 n 회 갱신할 만큼 기다린다 (10클럭마다 Tick)
    task wait_ticks(input integer n);
        begin
            tick_en = 1'b1;
            repeat (n * 10 + 12) @(posedge ACLK);
            tick_en = 1'b0;
            repeat (2) @(posedge ACLK);
        end
    endtask

    //--------------------------------------------------------------------------
    // Split-channel BFM (2026-07-30 추가)
    //
    // 위의 axi_write 는 AW 와 W 를 항상 같은 클럭에 올린다. 그래서 채널 도착
    // 순서가 어긋나는 상황을 전혀 만들지 못한다. 아래 task 들은 AW/W/AR 을
    // 따로 구동해서 순서를 바꾸고 응답에 backpressure 를 건다.
    //
    // READY 는 DUT 내부 레지스터(aw_pending/w_pending/axi_bvalid)로만 결정되고
    // VALID 에 의존하지 않으므로, negedge 에서 읽으면 안정된 값이다.
    //--------------------------------------------------------------------------
    task automatic drive_aw(input [5:0] addr, input integer delay);
        begin
            repeat (delay) @(negedge ACLK);
            AWADDR  = addr;
            AWVALID = 1'b1;
            while (!AWREADY) @(negedge ACLK);
            @(posedge ACLK);            // 이 edge 에서 AW Handshake 성립
            @(negedge ACLK);
            AWVALID = 1'b0;
        end
    endtask

    task automatic drive_w(input [31:0] data, input [3:0] strb, input integer delay);
        begin
            repeat (delay) @(negedge ACLK);
            WDATA  = data;
            WSTRB  = strb;
            WVALID = 1'b1;
            while (!WREADY) @(negedge ACLK);
            @(posedge ACLK);            // 이 edge 에서 W Handshake 성립
            @(negedge ACLK);
            WVALID = 1'b0;
            WSTRB  = 4'hF;              // 기본값 복구
        end
    endtask

    // BVALID 가 뜬 뒤 hold 클럭 동안 BREADY 를 낮게 유지하고, 그 사이
    // BVALID/BRESP 가 유지되는지, 새 요청이 차단되는지 확인한다.
    task automatic wait_b(input integer hold);
        integer i;
        begin
            while (!BVALID) @(negedge ACLK);
            for (i = 0; i < hold; i = i + 1) begin
                if (!BVALID) begin
                    errors = errors + 1;
                    $display("  [FAIL] BREADY 지연 중 BVALID 가 내려감 (i=%0d)", i);
                end
                if (BRESP !== 2'b00) begin
                    errors = errors + 1;
                    $display("  [FAIL] BREADY 지연 중 BRESP 변경 = %b", BRESP);
                end
                if (AWREADY || WREADY) begin
                    errors = errors + 1;
                    $display("  [FAIL] 응답 미완료 중 AWREADY/WREADY 가 열림 (%b/%b)",
                             AWREADY, WREADY);
                end
                @(negedge ACLK);
            end
            BREADY = 1'b1;
            @(posedge ACLK);
            @(negedge ACLK);
            BREADY = 1'b0;
        end
    endtask

    // AW/W 순서와 BREADY 지연을 지정하는 Write
    task automatic axi_write_split(input [5:0]  addr,
                                   input [31:0] data,
                                   input [3:0]  strb,
                                   input integer aw_delay,
                                   input integer w_delay,
                                   input integer b_hold);
        begin
            @(negedge ACLK);
            fork
                drive_aw(addr, aw_delay);
                drive_w(data, strb, w_delay);
            join
            wait_b(b_hold);
        end
    endtask

    // RREADY 를 hold 클럭 지연시키는 Read. 그 사이 RVALID/RDATA 유지 확인.
    task automatic axi_read_delayed(input [5:0] addr, input integer hold,
                                    output [31:0] data);
        integer i;
        reg [31:0] first;
        begin
            @(negedge ACLK);
            ARADDR = addr; ARVALID = 1'b1;
            while (!ARREADY) @(negedge ACLK);
            @(posedge ACLK);
            @(negedge ACLK);
            ARVALID = 1'b0;
            while (!RVALID) @(negedge ACLK);
            first = RDATA;
            for (i = 0; i < hold; i = i + 1) begin
                if (!RVALID) begin
                    errors = errors + 1;
                    $display("  [FAIL] RREADY 지연 중 RVALID 가 내려감 (i=%0d)", i);
                end
                if (RDATA !== first) begin
                    errors = errors + 1;
                    $display("  [FAIL] RREADY 지연 중 RDATA 변경 0x%08h -> 0x%08h",
                             first, RDATA);
                end
                @(negedge ACLK);
            end
            data   = RDATA;
            RREADY = 1'b1;
            @(posedge ACLK);
            @(negedge ACLK);
            RREADY = 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // AXI Protocol Monitor
    //   - Stall (VALID=1, READY=0) 구간에서 VALID/Payload 가 변하면 위반
    //   - Handshake 횟수를 세어 AW/W/B, AR/R 균형을 확인한다
    //--------------------------------------------------------------------------
    integer aw_hs = 0, w_hs = 0, b_hs = 0, ar_hs = 0, r_hs = 0;
    integer protocol_errors = 0;

    reg        p_awvalid = 0, p_awready = 0;
    reg [5:0]  p_awaddr  = 0;
    reg        p_wvalid  = 0, p_wready  = 0;
    reg [31:0] p_wdata   = 0;
    reg [3:0]  p_wstrb   = 0;
    reg        p_bvalid  = 0, p_bready  = 0;
    reg [1:0]  p_bresp   = 0;
    reg        p_arvalid = 0, p_arready = 0;
    reg [5:0]  p_araddr  = 0;
    reg        p_rvalid  = 0, p_rready  = 0;
    reg [31:0] p_rdata   = 0;
    reg [1:0]  p_rresp   = 0;

    always @(posedge ACLK) begin
        if (!ARESETN) begin
            aw_hs <= 0; w_hs <= 0; b_hs <= 0; ar_hs <= 0; r_hs <= 0;
            p_awvalid <= 0; p_awready <= 0; p_awaddr <= 0;
            p_wvalid  <= 0; p_wready  <= 0; p_wdata  <= 0; p_wstrb <= 0;
            p_bvalid  <= 0; p_bready  <= 0; p_bresp  <= 0;
            p_arvalid <= 0; p_arready <= 0; p_araddr <= 0;
            p_rvalid  <= 0; p_rready  <= 0; p_rdata  <= 0; p_rresp <= 0;
        end
        else begin
            if (AWVALID && AWREADY) aw_hs <= aw_hs + 1;
            if (WVALID  && WREADY ) w_hs  <= w_hs  + 1;
            if (BVALID  && BREADY ) b_hs  <= b_hs  + 1;
            if (ARVALID && ARREADY) ar_hs <= ar_hs + 1;
            if (RVALID  && RREADY ) r_hs  <= r_hs  + 1;

            if (p_awvalid && !p_awready)
                if (!AWVALID || (AWADDR !== p_awaddr)) begin
                    protocol_errors = protocol_errors + 1;
                    $display("[AXI PROTOCOL FAIL] AW Stall 중 VALID/ADDR 변경, 시간=%0t", $time);
                end

            if (p_wvalid && !p_wready)
                if (!WVALID || (WDATA !== p_wdata) || (WSTRB !== p_wstrb)) begin
                    protocol_errors = protocol_errors + 1;
                    $display("[AXI PROTOCOL FAIL] W Stall 중 VALID/DATA/STRB 변경, 시간=%0t", $time);
                end

            if (p_arvalid && !p_arready)
                if (!ARVALID || (ARADDR !== p_araddr)) begin
                    protocol_errors = protocol_errors + 1;
                    $display("[AXI PROTOCOL FAIL] AR Stall 중 VALID/ADDR 변경, 시간=%0t", $time);
                end

            if (p_bvalid && !p_bready)
                if (!BVALID || (BRESP !== p_bresp)) begin
                    protocol_errors = protocol_errors + 1;
                    $display("[AXI PROTOCOL FAIL] B Stall 중 BVALID/BRESP 변경, 시간=%0t", $time);
                end

            if (p_rvalid && !p_rready)
                if (!RVALID || (RDATA !== p_rdata) || (RRESP !== p_rresp)) begin
                    protocol_errors = protocol_errors + 1;
                    $display("[AXI PROTOCOL FAIL] R Stall 중 RVALID/RDATA/RRESP 변경, 시간=%0t", $time);
                end

            p_awvalid <= AWVALID; p_awready <= AWREADY; p_awaddr <= AWADDR;
            p_wvalid  <= WVALID;  p_wready  <= WREADY;  p_wdata  <= WDATA; p_wstrb <= WSTRB;
            p_bvalid  <= BVALID;  p_bready  <= BREADY;  p_bresp  <= BRESP;
            p_arvalid <= ARVALID; p_arready <= ARREADY; p_araddr <= ARADDR;
            p_rvalid  <= RVALID;  p_rready  <= RREADY;  p_rdata  <= RDATA; p_rresp <= RRESP;
        end
    end

    //--------------------------------------------------------------------------
    initial begin
        repeat (5) @(negedge ACLK);
        ARESETN = 1;
        repeat (5) @(negedge ACLK);

        $display("=== A01 : ID / 리셋 기본값 확인 ===");
        axi_read(ADDR_ID, rd);            check32(rd, 32'h464D4752, "ID == FMGR");
        axi_read(ADDR_CTRL, rd);          check32(rd, 32'h0, "CTRL reset = 0 (ENABLE off)");
        axi_read(ADDR_CRITICAL_MASK, rd); check32(rd, 32'h4, "CRITICAL_MASK reset = 3'b100");
        axi_read(ADDR_PERSIST_LIMIT, rd); check32(rd, 32'd5, "PERSIST_LIMIT reset = 5");
        axi_read(ADDR_FAULT_DEVICE, rd);  check32(rd, 32'd3, "FAULT_DEVICE reset = 3");
        check_bit(fault_valid, 1'b0, "fault_valid low before ENABLE");

        $display("=== A02 : RW 레지스터 Write/Read ===");
        axi_write(ADDR_CRITICAL_MASK, 32'h7);
        axi_read (ADDR_CRITICAL_MASK, rd); check32(rd, 32'h7, "CRITICAL_MASK rw");
        axi_write(ADDR_CRITICAL_MASK, 32'h4);
        axi_read (ADDR_CRITICAL_MASK, rd); check32(rd, 32'h4, "CRITICAL_MASK restore");
        axi_write(ADDR_PERSIST_LIMIT, 32'd3);
        axi_read (ADDR_PERSIST_LIMIT, rd); check32(rd, 32'd3, "PERSIST_LIMIT rw");
        axi_write(ADDR_IRQ_EN, 32'h1);
        axi_read (ADDR_IRQ_EN, rd);        check32(rd, 32'h1, "IRQ_EN rw");

        $display("=== A03 : Read-only 레지스터에 Write 는 무시 ===");
        axi_write(ADDR_FAULT_LEVEL, 32'hFFFFFFFF);
        axi_read (ADDR_FAULT_LEVEL, rd);   check32(rd, 32'h0, "FAULT_LEVEL write ignored");
        axi_write(ADDR_FAULT_COUNT, 32'hFFFFFFFF);
        axi_read (ADDR_FAULT_COUNT, rd);   check32(rd, 32'h0, "FAULT_COUNT write ignored");
        axi_write(ADDR_ID, 32'h0);
        axi_read (ADDR_ID, rd);            check32(rd, 32'h464D4752, "ID write ignored");

        $display("=== A04 : ENABLE 후 FAULT_INPUT / Level 반영 ===");
        axi_write(ADDR_CTRL, 32'h1);                     // ENABLE=1
        axi_read (ADDR_CTRL, rd); check32(rd, 32'h1, "CTRL readback ENABLE");
        timeout = 3'b001; error_flag = 3'b000; critical_fault = 3'b000;
        repeat (6) @(posedge ACLK);
        check_bit(fault_valid, 1'b1, "fault_valid high after ENABLE");
        axi_read(ADDR_FAULT_INPUT, rd);  check32(rd, 32'h00000001, "FAULT_INPUT timeout[0]");
        axi_read(ADDR_FAULT_LEVEL, rd);  check32(rd, 32'd1, "level 1 (temporary)");
        axi_read(ADDR_FAULT_DEVICE, rd); check32(rd, 32'd0, "device 0");
        axi_read(ADDR_FAULT_CODE, rd);   check32(rd, 32'h01, "code FAULT_TIMEOUT");

        $display("=== A05 : 공통 eval_tick 으로 지속 Count 누적 -> Level 2 ===");
        wait_ticks(4);                                   // limit=3
        axi_read(ADDR_FAULT_LEVEL, rd);  check32(rd, 32'd2, "level 2 (persistent)");
        axi_read(ADDR_FAULT_COUNT, rd);
        checks = checks + 1;
        if (rd[7:0] < 8'd3 || rd[31:24] !== 8'd0) begin
            errors = errors + 1;
            $display("  [FAIL] FAULT_COUNT packing = 0x%08h (count0>=3, bit[31:24]=0 기대)", rd);
        end
        else $display("  [PASS] FAULT_COUNT packing  (0x%08h, count0=%0d)", rd, rd[7:0]);

        $display("=== A06 : IRQ 는 W1C 전까지 High 유지 (Level) ===");
        check_bit(irq, 1'b1, "irq high after fault change");
        repeat (50) @(posedge ACLK);
        check_bit(irq, 1'b1, "irq still high (not pulse)");
        axi_read(ADDR_IRQ_STATUS, rd); check32(rd, 32'h1, "IRQ_STATUS pending");
        axi_write(ADDR_IRQ_STATUS, 32'h1);               // W1C
        repeat (3) @(posedge ACLK);
        check_bit(irq, 1'b0, "irq cleared by W1C");
        axi_read(ADDR_IRQ_STATUS, rd); check32(rd, 32'h0, "IRQ_STATUS cleared");

        $display("=== A07 : W1C 는 0 을 쓰면 지우지 않는다 ===");
        critical_fault = 3'b100;                          // Device 2 = Mask -> Level 3
        repeat (6) @(posedge ACLK);
        axi_read(ADDR_FAULT_LEVEL, rd); check32(rd, 32'd3, "dev2 critical -> level 3");
        axi_read(ADDR_IRQ_STATUS, rd);  check32(rd, 32'h1, "pending set again");
        axi_write(ADDR_IRQ_STATUS, 32'h0);                // 0 쓰기 -> 유지되어야 함
        repeat (3) @(posedge ACLK);
        axi_read(ADDR_IRQ_STATUS, rd);  check32(rd, 32'h1, "write 0 does not clear");
        axi_write(ADDR_IRQ_STATUS, 32'h1);
        critical_fault = 3'b000;
        repeat (6) @(posedge ACLK);
        axi_write(ADDR_IRQ_STATUS, 32'h1);                // 복귀 Event Pending 정리

        $display("=== A08 : RESET_FAULT 는 활성 Fault 가 있으면 무시 (02 문서 6.1) ===");
        timeout = 3'b001;
        wait_ticks(4);                                    // count >= 3 -> level 2
        axi_read(ADDR_FAULT_COUNT, rd);
        $display("        reset 시도 전 count0 = %0d", rd[7:0]);
        pulse_max = 0;
        axi_write(ADDR_CTRL, 32'h3);                      // ENABLE=1 + RESET_FAULT(W1P)
        repeat (5) @(posedge ACLK);
        check_int_task(pulse_max, 1, "reset_fault_pulse width == 1");
        axi_read(ADDR_CTRL, rd);        check32(rd, 32'h1, "CTRL bit1 reads 0 (W1P)");
        axi_read(ADDR_FAULT_LEVEL, rd); check32(rd, 32'd2, "active fault -> level stays 2");
        axi_read(ADDR_FAULT_COUNT, rd);
        checks = checks + 1;
        if (rd[7:0] < 8'd3) begin
            errors = errors + 1;
            $display("  [FAIL] active fault -> count must NOT be cleared (count0=%0d)", rd[7:0]);
        end
        else $display("  [PASS] active fault -> count kept  (count0=%0d)", rd[7:0]);

        $display("=== A09 : Fault 제거 후 RESET_FAULT 가 Count/Pending Clear ===");
        timeout = 3'b000;
        repeat (6) @(posedge ACLK);
        axi_read(ADDR_FAULT_LEVEL, rd);  check32(rd, 32'd0, "level back to 0");
        axi_read(ADDR_IRQ_STATUS, rd);   check32(rd, 32'h1, "level change set pending");
        axi_write(ADDR_CTRL, 32'h3);                      // RESET_FAULT, 이번엔 Fault 없음
        repeat (5) @(posedge ACLK);
        axi_read(ADDR_FAULT_COUNT, rd);  check32(rd, 32'h0, "no fault -> FAULT_COUNT cleared");
        axi_read(ADDR_IRQ_STATUS, rd);   check32(rd, 32'h0, "no fault -> pending cleared");
        check_bit(irq, 1'b0, "irq low after reset_fault");

        $display("=== A10 : ENABLE=0 안전 출력 (00 문서 12.1) ===");
        critical_fault = 3'b100;
        repeat (6) @(posedge ACLK);
        axi_read(ADDR_FAULT_LEVEL, rd);  check32(rd, 32'd3, "level 3 before disable");
        axi_write(ADDR_IRQ_STATUS, 32'h1);
        axi_write(ADDR_CTRL, 32'h0);                      // ENABLE=0
        repeat (6) @(posedge ACLK);
        axi_read(ADDR_FAULT_LEVEL, rd);  check32(rd, 32'd0, "disable -> FAULT_LEVEL 0");
        axi_read(ADDR_FAULT_DEVICE, rd); check32(rd, 32'd3, "disable -> FAULT_DEVICE 3");
        axi_read(ADDR_FAULT_CODE, rd);   check32(rd, 32'h0, "disable -> FAULT_CODE NONE");
        axi_read(ADDR_FAULT_COUNT, rd);  check32(rd, 32'h0, "disable -> FAULT_COUNT 0");
        check_bit(fault_valid, 1'b0, "disable -> fault_valid 0");
        axi_read(ADDR_IRQ_STATUS, rd);   check32(rd, 32'h0, "disable -> no new pending");
        axi_read(ADDR_FAULT_INPUT, rd);  check32(rd, 32'h00040000, "FAULT_INPUT critical[2] 유지");

        critical_fault = 3'b000;
        repeat (6) @(posedge ACLK);
        axi_write(ADDR_IRQ_STATUS, 32'h1);        // 잔여 Pending 정리
        repeat (3) @(posedge ACLK);

        //======================================================================
        // 여기부터 AXI4-Lite 규격 항목 (2026-07-30 추가)
        // 진입 시점 상태 : ENABLE=0, CRITICAL_MASK=4, PERSIST_LIMIT=3,
        //                  IRQ_EN=1, IRQ_STATUS=0, fault 입력 전부 0
        //======================================================================

        $display("=== A11 : AW 먼저 도착 (W 를 5클럭 지연) ===");
        axi_write_split(ADDR_PERSIST_LIMIT, 32'd7, 4'hF, 0, 5, 0);
        axi_read(ADDR_PERSIST_LIMIT, rd);
        check32(rd, 32'd7, "AW-first write applied");

        $display("=== A12 : W 먼저 도착 (구 래퍼가 교착하던 케이스) ===");
        axi_read(ADDR_CTRL, rd); check32(rd, 32'h0, "before W-first: CTRL == 0");

        // W 만 먼저 올린다. AW 는 아직 없다.
        @(negedge ACLK);
        WDATA  = 32'hCAFEBABE;
        WSTRB  = 4'hF;
        WVALID = 1'b1;
        while (!WREADY) @(negedge ACLK);
        @(posedge ACLK);                          // W Handshake 성립
        @(negedge ACLK);
        WVALID = 1'b0;

        // AW 가 없는 동안 절대 Commit 되면 안 된다.
        for (i = 0; i < 6; i = i + 1) begin
            if (BVALID) begin
                errors = errors + 1;
                $display("  [FAIL] AW 없이 BVALID 발생 (i=%0d) - 조기 Commit", i);
            end
            @(negedge ACLK);
        end
        check_bit(dut.reg_enable, 1'b0,
                  "W-first: data did NOT leak into CTRL");
        check32({29'd0, dut.reg_critical_mask}, 32'h4,
                "W-first: target untouched until AW arrives");

        // 이제 AW 를 보낸다. 여기서 BVALID 가 나와야 한다 (구 래퍼는 여기서 교착).
        @(negedge ACLK);
        AWADDR  = ADDR_CRITICAL_MASK;
        AWVALID = 1'b1;
        while (!AWREADY) @(negedge ACLK);
        @(posedge ACLK);                          // AW Handshake 성립
        @(negedge ACLK);
        AWVALID = 1'b0;
        wait_b(0);                                // BVALID 를 기다렸다가 BREADY

        axi_read(ADDR_CRITICAL_MASK, rd);
        check32(rd, 32'h6, "W-first write landed at correct addr (0xBE[2:0]=6)");
        axi_read(ADDR_CTRL, rd);
        check32(rd, 32'h0, "after W-first: CTRL still clean");

        axi_write(ADDR_CRITICAL_MASK, 32'h4);     // 기본값 복구
        axi_read(ADDR_CRITICAL_MASK, rd); check32(rd, 32'h4, "CRITICAL_MASK restored");

        $display("=== A13 : WSTRB - byte0 이 꺼진 Write 는 전부 무시 ===");
        axi_write(ADDR_PERSIST_LIMIT, 32'd10);
        axi_read (ADDR_PERSIST_LIMIT, rd); check32(rd, 32'd10, "baseline PERSIST_LIMIT = 10");

        axi_write_split(ADDR_PERSIST_LIMIT, 32'h000000FF, 4'b1110, 0, 0, 0);
        axi_read(ADDR_PERSIST_LIMIT, rd);
        check32(rd, 32'd10, "WSTRB=1110 (byte0 off) -> RW ignored");

        axi_write_split(ADDR_PERSIST_LIMIT, 32'h000000FF, 4'b0000, 0, 0, 0);
        axi_read(ADDR_PERSIST_LIMIT, rd);
        check32(rd, 32'd10, "WSTRB=0000 -> RW ignored");

        axi_write_split(ADDR_PERSIST_LIMIT, 32'd3, 4'b0001, 0, 0, 0);
        axi_read(ADDR_PERSIST_LIMIT, rd);
        check32(rd, 32'd3, "WSTRB=0001 (byte0 on) -> RW applied");

        // W1P : byte0 이 꺼져 있으면 Pulse 자체가 나오면 안 된다
        pulse_max = 0;
        axi_write_split(ADDR_CTRL, 32'h3, 4'b1110, 0, 0, 0);
        repeat (5) @(posedge ACLK);
        check_int_task(pulse_max, 0, "WSTRB byte0 off -> no W1P pulse");
        check_bit(dut.reg_enable, 1'b0, "WSTRB byte0 off -> ENABLE unchanged");

        // W1C : Pending 을 만들고 byte0 off 로는 안 지워지는지 본다
        axi_write(ADDR_CTRL, 32'h1);              // ENABLE=1
        timeout = 3'b001;
        repeat (6) @(posedge ACLK);
        axi_read(ADDR_IRQ_STATUS, rd); check32(rd, 32'h1, "fault sets IRQ pending");
        timeout = 3'b000;                          // Fault 제거 (재Set 방지)
        repeat (8) @(posedge ACLK);

        axi_write_split(ADDR_IRQ_STATUS, 32'h1, 4'b1110, 0, 0, 0);
        repeat (3) @(posedge ACLK);
        axi_read(ADDR_IRQ_STATUS, rd);
        check32(rd, 32'h1, "WSTRB byte0 off -> W1C ignored");

        axi_write_split(ADDR_IRQ_STATUS, 32'h1, 4'b0001, 0, 0, 0);
        repeat (3) @(posedge ACLK);
        axi_read(ADDR_IRQ_STATUS, rd);
        check32(rd, 32'h0, "WSTRB byte0 on -> W1C applied");

        $display("=== A14 : BREADY / RREADY Backpressure ===");
        // wait_b(8) 안에서 BVALID 유지, BRESP 고정, AWREADY/WREADY 차단을 검사한다
        axi_write_split(ADDR_PERSIST_LIMIT, 32'd9, 4'hF, 0, 0, 8);
        axi_read(ADDR_PERSIST_LIMIT, rd);
        check32(rd, 32'd9, "write OK with BREADY stalled 8 clks");

        axi_read_delayed(ADDR_PERSIST_LIMIT, 6, rd);
        check32(rd, 32'd9, "read data held with RREADY stalled 6 clks");

        $display("=== A15 : 백투백 연속 요청 (요청 유실 없음) ===");
        axi_write(ADDR_CRITICAL_MASK, 32'h7);
        axi_write(ADDR_PERSIST_LIMIT, 32'd4);
        axi_write(ADDR_IRQ_EN,        32'h0);
        axi_read(ADDR_CRITICAL_MASK, rd); check32(rd, 32'h7, "back-to-back write 1/3");
        axi_read(ADDR_PERSIST_LIMIT, rd); check32(rd, 32'd4, "back-to-back write 2/3");
        axi_read(ADDR_IRQ_EN,        rd); check32(rd, 32'h0, "back-to-back write 3/3");

        // AW/W 순서를 섞은 연속 Write 도 유실 없이 처리되어야 한다
        axi_write_split(ADDR_CRITICAL_MASK, 32'h5, 4'hF, 0, 3, 0);   // AW 먼저
        axi_write_split(ADDR_PERSIST_LIMIT, 32'd6, 4'hF, 3, 0, 0);   // W  먼저
        axi_read(ADDR_CRITICAL_MASK, rd); check32(rd, 32'h5, "mixed AW/W order write 1/2");
        axi_read(ADDR_PERSIST_LIMIT, rd); check32(rd, 32'd6, "mixed AW/W order write 2/2");

        repeat (4) @(posedge ACLK);

        $display("=== A16 : AXI Handshake 균형 / Protocol Monitor ===");
        check_int_task(aw_hs, w_hs, "AW handshake count == W handshake count");
        check_int_task(b_hs,  aw_hs, "B  handshake count == AW handshake count");
        check_int_task(r_hs,  ar_hs, "R  handshake count == AR handshake count");
        check_int_task(protocol_errors, 0, "AXI protocol monitor violations == 0");
        $display("        AW/W/B = %0d/%0d/%0d,  AR/R = %0d/%0d",
                 aw_hs, w_hs, b_hs, ar_hs, r_hs);

        $display("");
        $display("=====================================");
        $display(" checks = %0d, errors = %0d  -> %0s", checks, errors,
                 (errors == 0) ? "ALL PASS" : "FAIL");
        $display("=====================================");
        $finish;
    end

endmodule
