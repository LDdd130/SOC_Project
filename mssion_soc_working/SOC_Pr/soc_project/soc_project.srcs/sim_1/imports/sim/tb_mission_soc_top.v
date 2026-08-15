`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 파일 : tb_mission_soc_top.v
// 역할 : Heartbeat Monitor -> Fault Manager -> Safety Controller 통합 Testbench
//
// 04 통합 체크리스트가 요구하는 "세 IP 를 실제로 연결한 상태의 정책 검증"을
// 시뮬레이션으로 확인한다. 개별 IP TB 는 각자 입력을 TB 가 직접 넣지만,
// 여기서는 앞단 IP 의 출력이 뒷단 IP 의 입력이 되므로 체인 전체가 맞물려야
// 통과한다.
//
// 배선은 mission_soc.bd 의 net 목록을 그대로 옮긴 것이다 :
//
//   eval_tick_generator.eval_tick ─┬─> fault_manager_axi.eval_tick
//                                  └─> safety_controller_axi.eval_tick
//   axi_gpio_1.gpio_io_o          ──> heartbeat_monitor_axi.heartbeat_async
//   axi_gpio_0.gpio_io_o          ──> fault_manager_axi.error_flag
//   axi_gpio_0.gpio2_io_o         ──> fault_manager_axi.critical_fault
//   heartbeat_monitor_axi.timeout ──> fault_manager_axi.timeout
//   fault_manager_axi.fault_level ─┐
//                    .fault_device ─┼─> safety_controller_axi
//                    .fault_code   ─┤
//                    .fault_valid  ─┘
//
// GPIO 는 MicroBlaze 출력 전용이므로 TB 의 reg 로 대체한다 (00 문서 12.3 :
// 물리 SW/BTN 경로는 이번 빌드 범위 밖, UART/GPIO 주입으로 대체).
//
// eval_tick_generator 의 DIVISOR 는 실제로 100_000 (100MHz 에서 1ms) 이지만
// 시뮬레이션 시간이 감당이 안 되므로 20 으로 줄인다. eval_tick 의 "주기"가
// 아니라 "Tick 이 올 때마다 지속 Count 가 오르는가"가 검증 대상이라 정책
// 판정에는 영향이 없다.
//////////////////////////////////////////////////////////////////////////////////

module tb_mission_soc_top;

    //==========================================================================
    // 레지스터 맵 (00~03 문서 확정 맵)
    //==========================================================================
    localparam HB_CTRL        = 6'h00, HB_STATUS      = 6'h04,
               HB_TIMEOUT0    = 6'h08, HB_TIMEOUT1    = 6'h0C,
               HB_TIMEOUT2    = 6'h10, HB_LAST_COUNT0 = 6'h14,
               HB_IRQ_EN      = 6'h20, HB_IRQ_STATUS  = 6'h24;

    localparam FM_CTRL        = 6'h00, FM_FAULT_INPUT = 6'h04,
               FM_CRIT_MASK   = 6'h08, FM_PERSIST_LIM = 6'h0C,
               FM_LEVEL       = 6'h10, FM_DEVICE      = 6'h14,
               FM_CODE        = 6'h18, FM_COUNT       = 6'h1C,
               FM_IRQ_EN      = 6'h20, FM_IRQ_STATUS  = 6'h24;

    localparam SC_CTRL        = 6'h00, SC_STATE       = 6'h04,
               SC_OUT_EN      = 6'h08, SC_DEGRADE_MSK = 6'h0C,
               SC_RECOV_CNT   = 6'h10, SC_STATE_TIMER = 6'h14,
               SC_IRQ_EN      = 6'h18, SC_IRQ_STATUS  = 6'h1C;

    localparam ST_NORMAL = 2'b00, ST_WARNING = 2'b01,
               ST_DEGRADED = 2'b10, ST_SAFE = 2'b11;

    localparam BUS_HB = 0, BUS_FM = 1, BUS_SC = 2;

    //==========================================================================
    // Clock / Reset
    //==========================================================================
    reg clk = 0;
    always #5 clk = ~clk;                 // 100 MHz (00 문서 5.1)

    reg aresetn = 0;
    wire reset = ~aresetn;                // eval_tick_generator 는 active high

    //==========================================================================
    // GPIO 대체 입력
    //==========================================================================
    reg [2:0] gpio_error_flag    = 3'b000;   // axi_gpio_0 gpio_io_o
    reg [2:0] gpio_critical      = 3'b000;   // axi_gpio_0 gpio2_io_o
    reg [2:0] hb_beat_en         = 3'b000;   // axi_gpio_1 gpio_io_o 를 만드는 소스

    // Heartbeat 는 주기 Pulse 다. hb_beat_en 이 1 인 device 만 5클럭마다 1클럭
    // High 를 낸다. HB 채널은 2FF 동기화 후 상승 에지에서 Counter 를 0으로
    // 되돌리므로 이 폭이면 충분하다.
    reg  [2:0] heartbeat_async = 3'b000;
    integer    beat_div = 0;
    always @(posedge clk) begin
        heartbeat_async <= 3'b000;
        if (!aresetn) beat_div <= 0;
        else if (beat_div >= 4) begin
            beat_div        <= 0;
            heartbeat_async <= hb_beat_en;
        end
        else beat_div <= beat_div + 1;
    end

    //==========================================================================
    // IP 간 연결선 (BD net 그대로)
    //==========================================================================
    wire        eval_tick;
    wire [2:0]  hb_alive, hb_timeout;
    wire        hb_irq;
    wire [1:0]  fm_level, fm_device;
    wire [7:0]  fm_code;
    wire        fm_valid, fm_irq;
    wire [1:0]  sc_state;
    wire [2:0]  sc_out_en;
    wire        sc_act_en, sc_ctrl_valid, sc_irq;
    wire [31:0] sc_state_timer;

    //==========================================================================
    // AXI4-Lite 3 채널 (MicroBlaze 대체)
    //==========================================================================
    reg  [5:0]  hb_awaddr=0; reg hb_awvalid=0; wire hb_awready;
    reg  [31:0] hb_wdata=0;  reg [3:0] hb_wstrb=4'hF; reg hb_wvalid=0; wire hb_wready;
    wire [1:0]  hb_bresp;    wire hb_bvalid; reg hb_bready=0;
    reg  [5:0]  hb_araddr=0; reg hb_arvalid=0; wire hb_arready;
    wire [31:0] hb_rdata;    wire [1:0] hb_rresp; wire hb_rvalid; reg hb_rready=0;

    reg  [5:0]  fm_awaddr=0; reg fm_awvalid=0; wire fm_awready;
    reg  [31:0] fm_wdata=0;  reg [3:0] fm_wstrb=4'hF; reg fm_wvalid=0; wire fm_wready;
    wire [1:0]  fm_bresp;    wire fm_bvalid; reg fm_bready=0;
    reg  [5:0]  fm_araddr=0; reg fm_arvalid=0; wire fm_arready;
    wire [31:0] fm_rdata;    wire [1:0] fm_rresp; wire fm_rvalid; reg fm_rready=0;

    reg  [4:0]  sc_awaddr=0; reg sc_awvalid=0; wire sc_awready;
    reg  [31:0] sc_wdata=0;  reg [3:0] sc_wstrb=4'hF; reg sc_wvalid=0; wire sc_wready;
    wire [1:0]  sc_bresp;    wire sc_bvalid; reg sc_bready=0;
    reg  [4:0]  sc_araddr=0; reg sc_arvalid=0; wire sc_arready;
    wire [31:0] sc_rdata;    wire [1:0] sc_rresp; wire sc_rvalid; reg sc_rready=0;

    // bus 인덱스로 고르기 위한 묶음
    wire [2:0] v_awready = {sc_awready, fm_awready, hb_awready};
    wire [2:0] v_wready  = {sc_wready,  fm_wready,  hb_wready};
    wire [2:0] v_bvalid  = {sc_bvalid,  fm_bvalid,  hb_bvalid};
    wire [2:0] v_arready = {sc_arready, fm_arready, hb_arready};
    wire [2:0] v_rvalid  = {sc_rvalid,  fm_rvalid,  hb_rvalid};

    //==========================================================================
    // DUT : BD 와 동일한 구성
    //==========================================================================
    eval_tick_generator #(.DIVISOR(20)) u_tick (
        .clk(clk), .reset(reset), .eval_tick(eval_tick));

    heartbeat_monitor_axi #(.C_S_AXI_DATA_WIDTH(32), .C_S_AXI_ADDR_WIDTH(6)) u_hb (
        .heartbeat_async(heartbeat_async),
        .alive(hb_alive), .timeout(hb_timeout), .irq(hb_irq),
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(aresetn),
        .S_AXI_AWADDR(hb_awaddr), .S_AXI_AWPROT(3'b000),
        .S_AXI_AWVALID(hb_awvalid), .S_AXI_AWREADY(hb_awready),
        .S_AXI_WDATA(hb_wdata), .S_AXI_WSTRB(hb_wstrb),
        .S_AXI_WVALID(hb_wvalid), .S_AXI_WREADY(hb_wready),
        .S_AXI_BRESP(hb_bresp), .S_AXI_BVALID(hb_bvalid), .S_AXI_BREADY(hb_bready),
        .S_AXI_ARADDR(hb_araddr), .S_AXI_ARPROT(3'b000),
        .S_AXI_ARVALID(hb_arvalid), .S_AXI_ARREADY(hb_arready),
        .S_AXI_RDATA(hb_rdata), .S_AXI_RRESP(hb_rresp),
        .S_AXI_RVALID(hb_rvalid), .S_AXI_RREADY(hb_rready));

    fault_manager_axi u_fm (
        .timeout(hb_timeout),                 // BD : HB.timeout -> FM.timeout
        .error_flag(gpio_error_flag),
        .critical_fault(gpio_critical),
        .eval_tick(eval_tick),
        .fault_level(fm_level), .fault_device(fm_device),
        .fault_code(fm_code), .fault_valid(fm_valid), .irq(fm_irq),
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(aresetn),
        .S_AXI_AWADDR(fm_awaddr), .S_AXI_AWPROT(3'b000),
        .S_AXI_AWVALID(fm_awvalid), .S_AXI_AWREADY(fm_awready),
        .S_AXI_WDATA(fm_wdata), .S_AXI_WSTRB(fm_wstrb),
        .S_AXI_WVALID(fm_wvalid), .S_AXI_WREADY(fm_wready),
        .S_AXI_BRESP(fm_bresp), .S_AXI_BVALID(fm_bvalid), .S_AXI_BREADY(fm_bready),
        .S_AXI_ARADDR(fm_araddr), .S_AXI_ARPROT(3'b000),
        .S_AXI_ARVALID(fm_arvalid), .S_AXI_ARREADY(fm_arready),
        .S_AXI_RDATA(fm_rdata), .S_AXI_RRESP(fm_rresp),
        .S_AXI_RVALID(fm_rvalid), .S_AXI_RREADY(fm_rready));

    safety_controller_axi #(.C_S_AXI_DATA_WIDTH(32), .C_S_AXI_ADDR_WIDTH(5)) u_sc (
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(aresetn),
        .S_AXI_AWADDR(sc_awaddr), .S_AXI_AWVALID(sc_awvalid), .S_AXI_AWREADY(sc_awready),
        .S_AXI_WDATA(sc_wdata), .S_AXI_WSTRB(sc_wstrb),
        .S_AXI_WVALID(sc_wvalid), .S_AXI_WREADY(sc_wready),
        .S_AXI_BRESP(sc_bresp), .S_AXI_BVALID(sc_bvalid), .S_AXI_BREADY(sc_bready),
        .S_AXI_ARADDR(sc_araddr), .S_AXI_ARVALID(sc_arvalid), .S_AXI_ARREADY(sc_arready),
        .S_AXI_RDATA(sc_rdata), .S_AXI_RRESP(sc_rresp),
        .S_AXI_RVALID(sc_rvalid), .S_AXI_RREADY(sc_rready),
        .fault_level(fm_level), .fault_device(fm_device),   // BD : FM -> SC
        .fault_code(fm_code), .fault_valid(fm_valid),
        .eval_tick(eval_tick),
        .system_state(sc_state), .output_enable(sc_out_en),
        .actuator_enable(sc_act_en), .control_valid(sc_ctrl_valid),
        .state_timer(sc_state_timer), .irq(sc_irq));

    //==========================================================================
    // 검사 인프라
    //==========================================================================
    integer checks = 0, errors = 0;
    reg [31:0] rd;

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

    // 체인 상태를 한 줄에 확인한다. 통합 TB 의 핵심 검사다.
    task check_chain(input [2:0] exp_to,   input [1:0] exp_lvl,
                     input [1:0] exp_state, input [2:0] exp_out,
                     input [8*120:1] name);
        begin
            checks = checks + 1;
            if (hb_timeout !== exp_to || fm_level !== exp_lvl ||
                sc_state !== exp_state || sc_out_en !== exp_out) begin
                errors = errors + 1;
                $display("  [FAIL] %0s", name);
                $display("         got : HB.timeout=%b FM.level=%0d SC.state=%b SC.out=%b",
                         hb_timeout, fm_level, sc_state, sc_out_en);
                $display("         exp : HB.timeout=%b FM.level=%0d SC.state=%b SC.out=%b",
                         exp_to, exp_lvl, exp_state, exp_out);
            end
            else
                $display("  [PASS] %0s  (HB.to=%b FM.lvl=%0d SC.st=%b SC.out=%b)",
                         name, hb_timeout, fm_level, sc_state, sc_out_en);
        end
    endtask

    //==========================================================================
    // AXI4-Lite BFM (bus 인덱스로 3개 슬레이브 공용)
    //==========================================================================
    task automatic axi_write(input integer bus, input [5:0] addr, input [31:0] data);
        begin
            @(negedge clk);
            case (bus)
              BUS_HB: begin hb_awaddr=addr;      hb_awvalid=1; hb_wdata=data;
                            hb_wstrb=4'hF;       hb_wvalid=1;  hb_bready=1; end
              BUS_FM: begin fm_awaddr=addr;      fm_awvalid=1; fm_wdata=data;
                            fm_wstrb=4'hF;       fm_wvalid=1;  fm_bready=1; end
              BUS_SC: begin sc_awaddr=addr[4:0]; sc_awvalid=1; sc_wdata=data;
                            sc_wstrb=4'hF;       sc_wvalid=1;  sc_bready=1; end
            endcase
            while (!(v_awready[bus] && v_wready[bus])) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            case (bus)
              BUS_HB: begin hb_awvalid=0; hb_wvalid=0; end
              BUS_FM: begin fm_awvalid=0; fm_wvalid=0; end
              BUS_SC: begin sc_awvalid=0; sc_wvalid=0; end
            endcase
            while (!v_bvalid[bus]) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            case (bus)
              BUS_HB: hb_bready=0;
              BUS_FM: fm_bready=0;
              BUS_SC: sc_bready=0;
            endcase
        end
    endtask

    task automatic axi_read(input integer bus, input [5:0] addr, output [31:0] data);
        begin
            @(negedge clk);
            case (bus)
              BUS_HB: begin hb_araddr=addr;      hb_arvalid=1; hb_rready=1; end
              BUS_FM: begin fm_araddr=addr;      fm_arvalid=1; fm_rready=1; end
              BUS_SC: begin sc_araddr=addr[4:0]; sc_arvalid=1; sc_rready=1; end
            endcase
            while (!v_arready[bus]) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            case (bus)
              BUS_HB: hb_arvalid=0;
              BUS_FM: fm_arvalid=0;
              BUS_SC: sc_arvalid=0;
            endcase
            while (!v_rvalid[bus]) @(negedge clk);
            case (bus)
              BUS_HB: data = hb_rdata;
              BUS_FM: data = fm_rdata;
              BUS_SC: data = sc_rdata;
            endcase
            @(posedge clk);
            @(negedge clk);
            case (bus)
              BUS_HB: hb_rready=0;
              BUS_FM: fm_rready=0;
              BUS_SC: sc_rready=0;
            endcase
        end
    endtask

    // eval_tick 을 n 번 지나갈 만큼 기다린다 (DIVISOR=20)
    task wait_eval_ticks(input integer n);
        integer seen;
        begin
            seen = 0;
            while (seen < n) begin
                @(posedge clk);
                if (eval_tick) seen = seen + 1;
            end
            repeat (4) @(posedge clk);
        end
    endtask

    //==========================================================================
    initial begin
        repeat (5) @(negedge clk);
        aresetn = 1;
        repeat (10) @(negedge clk);

        //----------------------------------------------------------------------
        $display("=== M01 : 리셋 직후 - 세 IP 모두 Disable, 안전 출력 ===");
        //----------------------------------------------------------------------
        axi_read(BUS_HB, HB_CTRL, rd); check32(rd, 32'h0, "HB CTRL = 0 (Disable)");
        axi_read(BUS_FM, FM_CTRL, rd); check32(rd, 32'h0, "FM CTRL = 0 (Disable)");
        axi_read(BUS_SC, SC_CTRL, rd); check32(rd, 32'h0, "SC CTRL = 0 (Disable)");
        check_chain(3'b000, 2'd0, ST_NORMAL, 3'b000,
                    "reset: chain is idle and outputs are safe");
        check_bit(sc_act_en,     1'b0, "reset: actuator_enable = 0");
        check_bit(sc_ctrl_valid, 1'b0, "reset: control_valid = 0");
        check_bit(hb_irq, 1'b0, "reset: HB irq low");
        check_bit(fm_irq, 1'b0, "reset: FM irq low");
        check_bit(sc_irq, 1'b0, "reset: SC irq low");

        //----------------------------------------------------------------------
        $display("=== M02 : 펌웨어 부팅 순서 그대로 초기화 (main.c 1~13단계) ===");
        //----------------------------------------------------------------------
        // 1~2. 세 IP Disable + 세 IRQ Disable (리셋 직후라 이미 0이지만 명세대로)
        axi_write(BUS_HB, HB_CTRL,   32'h0);
        axi_write(BUS_FM, FM_CTRL,   32'h0);
        axi_write(BUS_SC, SC_CTRL,   32'h0);
        axi_write(BUS_HB, HB_IRQ_EN, 32'h0);
        axi_write(BUS_FM, FM_IRQ_EN, 32'h0);
        axi_write(BUS_SC, SC_IRQ_EN, 32'h0);

        // 3~7. 전체 설정
        axi_write(BUS_HB, HB_TIMEOUT0,    32'd10);
        axi_write(BUS_HB, HB_TIMEOUT1,    32'd10);
        axi_write(BUS_HB, HB_TIMEOUT2,    32'd10);
        axi_write(BUS_FM, FM_CRIT_MASK,   32'b100);   // Device2 = Critical (00 문서 9.2)
        axi_write(BUS_FM, FM_PERSIST_LIM, 32'd3);
        axi_write(BUS_SC, SC_DEGRADE_MSK, 32'b110);
        axi_write(BUS_SC, SC_RECOV_CNT,   32'd3);

        // 8. 전체 Clear
        axi_write(BUS_HB, HB_CTRL,       32'h2);      // CLEAR_ALL (W1P)
        axi_write(BUS_HB, HB_IRQ_STATUS, 32'h7);
        axi_write(BUS_FM, FM_IRQ_STATUS, 32'h1);
        axi_write(BUS_SC, SC_IRQ_STATUS, 32'h1);

        // 10~11. FM/SC Enable -> HB Enable  (앞단보다 뒷단을 먼저 켠다)
        axi_write(BUS_FM, FM_CTRL, 32'h1);
        axi_write(BUS_SC, SC_CTRL, 32'h1);
        hb_beat_en = 3'b111;                          // 세 device 가 살아있다고 알림
        // ENABLE | AUTO_RECOVER. 펌웨어(hb_regs.c:38)와 같은 값이다.
        // AUTO_RECOVER=0 이면 Timeout Latch 가 CLEAR_ALL 전까지 안 풀려서
        // Heartbeat 가 돌아와도 FM 이 계속 Fault 를 보게 된다.
        axi_write(BUS_HB, HB_CTRL, 32'h5);

        // 12~13. IRQ Enable
        axi_write(BUS_FM, FM_IRQ_EN, 32'h1);
        axi_write(BUS_HB, HB_IRQ_EN, 32'h7);
        axi_write(BUS_SC, SC_IRQ_EN, 32'h1);

        repeat (40) @(posedge clk);
        axi_write(BUS_SC, SC_IRQ_STATUS, 32'h1);      // Enable 로 생긴 상태변화 정리
        axi_write(BUS_FM, FM_IRQ_STATUS, 32'h1);
        repeat (10) @(posedge clk);

        check_chain(3'b000, 2'd0, ST_NORMAL, 3'b111,
                    "boot done: NORMAL with all outputs enabled");
        check32({29'd0, hb_alive}, 32'h7, "boot done: all three devices alive");
        check_bit(sc_act_en,     1'b1, "boot done: actuator_enable = 1");
        check_bit(sc_ctrl_valid, 1'b1, "boot done: control_valid = 1");

        //----------------------------------------------------------------------
        $display("=== M03 : Device0 Heartbeat 정지 -> HB timeout -> FM Level1 -> SC WARNING ===");
        //----------------------------------------------------------------------
        hb_beat_en[0] = 1'b0;                         // Device0 만 멈춘다
        repeat (30) @(posedge clk);                   // TIMEOUT0=10 을 넘긴다

        check32({29'd0, hb_timeout}, 32'h1, "HB: only device0 timed out");
        check32({29'd0, hb_alive},   32'h6, "HB: device1/2 still alive");
        axi_read(BUS_FM, FM_LEVEL,  rd); check32(rd, 32'd1, "FM: level 1 (temporary)");
        axi_read(BUS_FM, FM_DEVICE, rd); check32(rd, 32'd0, "FM: device 0");
        axi_read(BUS_FM, FM_CODE,   rd); check32(rd, 32'h01, "FM: code = FAULT_TIMEOUT");
        check_bit(fm_valid, 1'b1, "FM: fault_valid high");
        check_chain(3'b001, 2'd1, ST_WARNING, 3'b111,
                    "chain: HB timeout -> FM lvl1 -> SC WARNING (outputs kept)");
        check_bit(hb_irq, 1'b1, "HB irq raised by timeout");
        check_bit(fm_irq, 1'b1, "FM irq raised by fault change");
        check_bit(sc_irq, 1'b1, "SC irq raised by state change");

        //----------------------------------------------------------------------
        $display("=== M04 : eval_tick 누적 -> FM Level2 -> SC DEGRADED ===");
        //----------------------------------------------------------------------
        wait_eval_ticks(5);                           // PERSIST_LIMIT=3 을 넘긴다

        axi_read(BUS_FM, FM_LEVEL, rd); check32(rd, 32'd2, "FM: level 2 (persistent)");
        axi_read(BUS_FM, FM_COUNT, rd);
        checks = checks + 1;
        if (rd[7:0] < 8'd3) begin
            errors = errors + 1;
            $display("  [FAIL] FM count0 must be >= PERSIST_LIMIT (got %0d)", rd[7:0]);
        end
        else $display("  [PASS] FM count0 >= PERSIST_LIMIT  (=%0d)", rd[7:0]);

        check_chain(3'b001, 2'd2, ST_DEGRADED, 3'b110,
                    "chain: FM lvl2 -> SC DEGRADED with DEGRADE_MASK=110");
        check_bit(sc_act_en,     1'b1, "DEGRADED: actuator still enabled");
        check_bit(sc_ctrl_valid, 1'b1, "DEGRADED: control still valid");

        //----------------------------------------------------------------------
        $display("=== M05 : Device2 Critical -> FM Level3 -> SC SAFE_MODE ===");
        //----------------------------------------------------------------------
        gpio_critical = 3'b100;                       // CRITICAL_MASK 와 일치
        repeat (20) @(posedge clk);

        axi_read(BUS_FM, FM_LEVEL,  rd); check32(rd, 32'd3, "FM: level 3 (critical)");
        axi_read(BUS_FM, FM_DEVICE, rd); check32(rd, 32'd2, "FM: device 2");
        check_chain(3'b001, 2'd3, ST_SAFE, 3'b000,
                    "chain: FM lvl3 -> SC SAFE_MODE, all outputs off");
        check_bit(sc_act_en,     1'b0, "SAFE_MODE: actuator_enable = 0");
        check_bit(sc_ctrl_valid, 1'b0, "SAFE_MODE: control_valid = 0");

        //----------------------------------------------------------------------
        $display("=== M06 : SAFE_MODE 는 Fault 가 사라져도 자동 복구하지 않는다 ===");
        //----------------------------------------------------------------------
        gpio_critical = 3'b000;
        hb_beat_en    = 3'b111;                       // Device0 Heartbeat 재개
        repeat (30) @(posedge clk);
        axi_write(BUS_FM, FM_CTRL, 32'h3);            // RESET_FAULT (Fault 없으니 적용)
        repeat (10) @(posedge clk);

        axi_read(BUS_FM, FM_LEVEL, rd); check32(rd, 32'd0, "FM: level back to 0");
        wait_eval_ticks(6);                           // 자동 복구 기회를 충분히 준다
        axi_read(BUS_SC, SC_STATE, rd);
        check32(rd, 32'd3, "SC: SAFE_MODE latched despite level 0");
        check32({29'd0, sc_out_en}, 32'h0, "SC: outputs stay off in SAFE_MODE");

        //----------------------------------------------------------------------
        $display("=== M07 : MANUAL_RESET (W1P) 으로만 NORMAL 복구 ===");
        //----------------------------------------------------------------------
        axi_write(BUS_SC, SC_CTRL, 32'h3);            // ENABLE + MANUAL_RESET
        repeat (10) @(posedge clk);
        axi_read(BUS_SC, SC_CTRL, rd);
        check32(rd, 32'h1, "SC: CTRL bit1 reads back 0 (W1P)");
        check_chain(3'b000, 2'd0, ST_NORMAL, 3'b111,
                    "chain: manual reset -> NORMAL, outputs restored");
        check_bit(sc_act_en,     1'b1, "recovered: actuator_enable = 1");
        check_bit(sc_ctrl_valid, 1'b1, "recovered: control_valid = 1");

        //----------------------------------------------------------------------
        $display("=== M08 : 세 IP IRQ 를 각각 W1C 로 내린다 ===");
        //----------------------------------------------------------------------
        axi_read(BUS_HB, HB_IRQ_STATUS, rd);
        checks = checks + 1;
        if (rd == 32'h0) begin
            errors = errors + 1;
            $display("  [FAIL] HB IRQ_STATUS should still hold a pending bit");
        end
        else $display("  [PASS] HB IRQ_STATUS holds pending  (0x%08h)", rd);

        axi_write(BUS_HB, HB_IRQ_STATUS, 32'h7);
        axi_write(BUS_FM, FM_IRQ_STATUS, 32'h1);
        axi_write(BUS_SC, SC_IRQ_STATUS, 32'h1);
        repeat (6) @(posedge clk);

        check_bit(hb_irq, 1'b0, "HB irq cleared by W1C");
        check_bit(fm_irq, 1'b0, "FM irq cleared by W1C");
        check_bit(sc_irq, 1'b0, "SC irq cleared by W1C");
        axi_read(BUS_HB, HB_IRQ_STATUS, rd); check32(rd, 32'h0, "HB IRQ_STATUS cleared");
        axi_read(BUS_FM, FM_IRQ_STATUS, rd); check32(rd, 32'h0, "FM IRQ_STATUS cleared");
        axi_read(BUS_SC, SC_IRQ_STATUS, rd); check32(rd, 32'h0, "SC IRQ_STATUS cleared");

        //----------------------------------------------------------------------
        $display("=== M09 : error_flag 경로도 같은 체인을 탄다 (GPIO 주입) ===");
        //----------------------------------------------------------------------
        gpio_error_flag = 3'b010;                     // Device1 error, Critical 아님
        repeat (20) @(posedge clk);
        axi_read(BUS_FM, FM_LEVEL,  rd); check32(rd, 32'd1, "FM: error_flag -> level 1");
        axi_read(BUS_FM, FM_DEVICE, rd); check32(rd, 32'd1, "FM: device 1");
        axi_read(BUS_SC, SC_STATE,  rd); check32(rd, 32'd1, "SC: WARNING from error_flag");

        wait_eval_ticks(5);
        axi_read(BUS_FM, FM_LEVEL, rd); check32(rd, 32'd2, "FM: error_flag persists -> level 2");
        axi_read(BUS_SC, SC_STATE, rd); check32(rd, 32'd2, "SC: DEGRADED from error_flag");

        //----------------------------------------------------------------------
        $display("=== M10 : Fault 제거 + RECOVERY_COUNT 만큼 eval_tick -> NORMAL 자동 복구 ===");
        //----------------------------------------------------------------------
        gpio_error_flag = 3'b000;
        repeat (20) @(posedge clk);
        axi_write(BUS_FM, FM_CTRL, 32'h3);            // RESET_FAULT
        repeat (10) @(posedge clk);
        axi_read(BUS_FM, FM_LEVEL, rd); check32(rd, 32'd0, "FM: level 0 after fault removed");

        wait_eval_ticks(8);                           // RECOVERY_COUNT=3 x 2단계
        check_chain(3'b000, 2'd0, ST_NORMAL, 3'b111,
                    "chain: auto recovery DEGRADED -> WARNING -> NORMAL");
        check_bit(sc_act_en,     1'b1, "auto recovered: actuator_enable = 1");
        check_bit(sc_ctrl_valid, 1'b1, "auto recovered: control_valid = 1");

        //----------------------------------------------------------------------
        $display("=== M11 : 전역 Disable 시 세 IP 모두 안전 출력 (00 문서 12.1) ===");
        //----------------------------------------------------------------------
        axi_write(BUS_HB, HB_CTRL, 32'h0);
        axi_write(BUS_FM, FM_CTRL, 32'h0);
        axi_write(BUS_SC, SC_CTRL, 32'h0);
        repeat (20) @(posedge clk);

        check_chain(3'b000, 2'd0, ST_NORMAL, 3'b000,
                    "global disable: chain idle, outputs off");
        check32({29'd0, hb_alive}, 32'h0, "global disable: no device reported alive");
        check_bit(fm_valid,      1'b0, "global disable: fault_valid = 0");
        check_bit(sc_act_en,     1'b0, "global disable: actuator_enable = 0");
        check_bit(sc_ctrl_valid, 1'b0, "global disable: control_valid = 0");

        $display("");
        $display("==========================================================");
        $display(" MISSION SoC INTEGRATION : checks = %0d, errors = %0d  -> %0s",
                 checks, errors, (errors == 0) ? "ALL PASS" : "FAIL");
        $display("==========================================================");
        $finish;
    end

endmodule
