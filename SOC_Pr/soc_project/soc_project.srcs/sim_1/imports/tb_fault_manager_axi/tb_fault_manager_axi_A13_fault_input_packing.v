`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 파일 : tb_fault_manager_axi_A13_fault_input_packing.v
// 역할 : fault_manager_axi Self-checking Testbench
//        04 통합 체크리스트 3장의 AXI 항목을 미리 검증한다.
//          1) 모든 레지스터 Read/Write, Read-only Write 무시
//          2) W1P 가 정확히 1 Clock Pulse
//          3) W1C 가 지정 비트만 Clear
//          4) IRQ 가 Clear 전까지 High 유지 (Level 방식)
//          5) RESET_FAULT 는 활성 Fault 가 있으면 무시, 없으면 Count/Pending Clear
//          6) ENABLE=0 안전 출력
//
// eval_tick 은 이 IP 가 만들지 않는다. 공통 eval_tick_generator 를 흉내내어
// TB 가 1클럭 Pulse 를 넣는다 (00 문서 5.2).
//////////////////////////////////////////////////////////////////////////////////

module tb_fault_manager_axi_A13_fault_input_packing;

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

    task check32(input [31:0] got, input [31:0] exp, input [8*44:1] name);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] %0s  got=0x%08h exp=0x%08h", name, got, exp);
            end
            else $display("  [ ok ] %0s  (0x%08h)", name, got);
        end
    endtask

    task check_bit(input got, input exp, input [8*44:1] name);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] %0s  got=%b exp=%b", name, got, exp);
            end
            else $display("  [ ok ] %0s  (%b)", name, got);
        end
    endtask

    task check_int_task(input integer got, input integer exp, input [8*44:1] name);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] %0s  got=%0d exp=%0d", name, got, exp);
            end
            else $display("  [ ok ] %0s  (=%0d)", name, got);
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
    initial begin
        repeat (5) @(negedge ACLK);
        ARESETN = 1'b1;
        repeat (5) @(negedge ACLK);

        // 기본 설정
        axi_write(ADDR_CRITICAL_MASK, 32'h00000004);
        axi_write(ADDR_PERSIST_LIMIT, 32'd3);
        axi_write(ADDR_CTRL, 32'h00000001);   // ENABLE=1
        repeat (5) @(posedge ACLK);

        $display("=== A13 : FAULT_INPUT error_flag packing 검증 ===");

        timeout        = 3'b000;
        error_flag     = 3'b010;
        critical_fault = 3'b000;
        repeat (6) @(posedge ACLK);

        axi_read(ADDR_FAULT_INPUT, rd);
        check32(rd, 32'h00000200, "FAULT_INPUT error_flag[1] packing");

        checks = checks + 1;
        if (rd[10:8] !== 3'b010 || rd[2:0] !== 3'b000 ||
            rd[18:16] !== 3'b000) begin
            errors = errors + 1;
            $display("  [FAIL] error_flag field split got=0x%08h", rd);
        end
        else $display("  [ ok ] FAULT_INPUT bit[10:8] == 3'b010");

        timeout        = 3'b001;
        error_flag     = 3'b010;
        critical_fault = 3'b100;
        repeat (6) @(posedge ACLK);

        axi_read(ADDR_FAULT_INPUT, rd);
        check32(rd, 32'h00040201, "FAULT_INPUT all fields packing");

        checks = checks + 1;
        if (rd[2:0] !== 3'b001 || rd[10:8] !== 3'b010 ||
            rd[18:16] !== 3'b100 || rd[31:19] !== 13'd0 ||
            rd[15:11] !== 5'd0 || rd[7:3] !== 5'd0) begin
            errors = errors + 1;
            $display("  [FAIL] all field split got=0x%08h", rd);
        end
        else $display("  [ ok ] timeout/error/critical field split");

        timeout        = 3'b000;
        error_flag     = 3'b000;
        critical_fault = 3'b000;
        repeat (4) @(posedge ACLK);

        $display("");
        $display("=====================================");
        $display(" checks = %0d, errors = %0d  -> %0s", checks, errors,
                 (errors == 0) ? "ALL PASS" : "FAIL");
        $display("=====================================");
        $finish;

    end

endmodule
