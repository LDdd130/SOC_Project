`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 파일 : tb_fault_manager_core.v
// 역할 : fault_manager_core Self-checking Testbench
//        02_MEMBER_B 8장의 필수 항목 21개를 모두 검사하고,
//        마지막에 입력 전수 조합을 Reference function 과 대조한다.
//
// 시뮬 시간을 줄이려고 공통 eval_tick 을 Task 로 직접 만들고
// persist_limit 도 작은 값(3)을 쓴다. RTL 구조는 실제 값도 수용한다.
//////////////////////////////////////////////////////////////////////////////////

module tb_fault_manager_core;

    localparam [1:0] LEVEL_0 = 2'b00, LEVEL_1 = 2'b01, LEVEL_2 = 2'b10, LEVEL_3 = 2'b11;
    localparam [7:0] F_NONE  = 8'h00, F_TIMEOUT = 8'h01, F_ERROR = 8'h02,
                     F_CRIT  = 8'h03, F_MULTI   = 8'h04;
    localparam [1:0] DEV0 = 2'b00, DEV1 = 2'b01, DEV2 = 2'b10, DEV_MN = 2'b11;

    reg clk = 0, reset = 1;
    always #5 clk = ~clk;                       // 100 MHz

    reg        enable          = 1'b1;
    reg        eval_tick       = 1'b0;          // 공통 eval_tick (00 문서 5.2)
    reg [2:0]  timeout         = 3'b000;
    reg [2:0]  error_flag      = 3'b000;
    reg [2:0]  critical_fault  = 3'b000;
    reg [2:0]  critical_mask   = 3'b100;        // Device 2 가 Critical
    reg [7:0]  persist_limit   = 8'd3;
    reg        reset_fault_pulse = 1'b0;

    wire [1:0] fault_level, fault_device;
    wire [7:0] fault_code;
    wire       fault_valid, fault_change_event;
    wire [7:0] fault_count0, fault_count1, fault_count2;

    fault_manager_core dut (
        .clk(clk), .reset(reset), .enable(enable),
        .eval_tick(eval_tick),
        .timeout(timeout), .error_flag(error_flag), .critical_fault(critical_fault),
        .critical_mask(critical_mask), .persist_limit(persist_limit),
        .reset_fault_pulse(reset_fault_pulse),
        .fault_level(fault_level), .fault_device(fault_device), .fault_code(fault_code),
        .fault_valid(fault_valid),
        .fault_count0(fault_count0), .fault_count1(fault_count1), .fault_count2(fault_count2),
        .fault_change_event(fault_change_event));

    integer errors = 0;
    integer checks = 0;
    integer event_cnt = 0;

    // fault_change_event 누적 (중복 Event 검사용).
    // posedge clk 로 감시하면 "이 edge 의 현재값"을 읽으므로 fault_change_event 가
    // 실제로 1이 되는 edge 보다 한 클럭 늦게 잡힌다 (RTL 은 정상, TB 감시 타이밍 버그).
    // 신호 자체의 상승 edge 로 감시하면 지연 없이 그 순간 바로 잡는다.
    always @(posedge fault_change_event) event_cnt = event_cnt + 1;

    //--------------------------------------------------------------------------
    // Task
    //--------------------------------------------------------------------------
    task do_tick;                               // 지속 Count 를 1회 갱신
        begin
            @(negedge clk); eval_tick = 1'b1;
            @(negedge clk); eval_tick = 1'b0;
            @(negedge clk);                     // 출력 등록 반영 대기
        end
    endtask

    task settle;                                // 입력 변경 후 출력 안정화 대기 (Tick 없음)
        begin
            repeat (3) @(negedge clk);
        end
    endtask

    task check(input [1:0] exp_level, input [1:0] exp_dev, input [7:0] exp_code,
               input [8*44:1] name);
        begin
            checks = checks + 1;
            if (fault_level !== exp_level || fault_device !== exp_dev || fault_code !== exp_code) begin
                errors = errors + 1;
                $display("  [FAIL] %0s", name);
                $display("         got level=%0d device=%0d code=0x%02h",
                         fault_level, fault_device, fault_code);
                $display("         exp level=%0d device=%0d code=0x%02h",
                         exp_level, exp_dev, exp_code);
            end
            else $display("  [PASS] %0s  (level=%0d dev=%0d code=0x%02h)",
                          name, fault_level, fault_device, fault_code);
        end
    endtask

    task check_int(input integer got, input integer exp, input [8*44:1] name);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] %0s  got=%0d exp=%0d", name, got, exp);
            end
            else $display("  [PASS] %0s  (=%0d)", name, got);
        end
    endtask

    task clear_inputs;
        begin
            timeout        = 3'b000;
            error_flag     = 3'b000;
            critical_fault = 3'b000;
            settle;
        end
    endtask

    //--------------------------------------------------------------------------
    // Reference model — 00 문서 10장 / 02 문서 3장 우선순위를 그대로 옮긴 함수.
    //   device_fault       = timeout | error_flag | critical_fault
    //   critical_condition = device_fault & critical_mask   <- Mask 는 모든 원인에 적용
    // 반환값 = {level[1:0], device[1:0], code[7:0]}
    //--------------------------------------------------------------------------
    function [11:0] ref_out;
        input [2:0] t, e, c, mask;
        input [2:0] phit;                   // 지속 판정이 성립한 장치
        reg   [2:0] df, cc, el;
        reg   [1:0] nf, nc, lvl, dev, sdev;
        reg   [7:0] cod, scode;
        begin
            df = t | e | c;
            cc = df & mask;                 // Critical 조건 (Timeout/Error/Critical 전부)
            el = e | c;                     // ERROR_CODE 로 볼 원인
            nf = {1'b0, df[0]} + {1'b0, df[1]} + {1'b0, df[2]};
            nc = {1'b0, cc[0]} + {1'b0, cc[1]} + {1'b0, cc[2]};

            if      (df[0]) sdev = DEV0;
            else if (df[1]) sdev = DEV1;
            else if (df[2]) sdev = DEV2;
            else            sdev = DEV_MN;

            case (sdev)
                DEV0:    scode = el[0] ? F_ERROR : F_TIMEOUT;
                DEV1:    scode = el[1] ? F_ERROR : F_TIMEOUT;
                DEV2:    scode = el[2] ? F_ERROR : F_TIMEOUT;
                default: scode = F_NONE;
            endcase

            lvl = LEVEL_0; dev = DEV_MN; cod = F_NONE;

            if (cc != 3'b000) begin                       // P1 Critical
                lvl = LEVEL_3; cod = F_CRIT;
                if (nc == 2'd1) begin
                    if      (cc[0]) dev = DEV0;
                    else if (cc[1]) dev = DEV1;
                    else            dev = DEV2;
                end
                else dev = DEV_MN;
            end
            else if (nf >= 2'd2) begin                    // P2 다중 장치
                lvl = LEVEL_3; cod = F_MULTI; dev = DEV_MN;
            end
            else if ((phit & df) != 3'b000) begin         // P3 지속
                lvl = LEVEL_2; dev = sdev; cod = scode;
            end
            else if (df != 3'b000) begin                  // P4 일시
                lvl = LEVEL_1; dev = sdev; cod = scode;
            end

            ref_out = {lvl, dev, cod};
        end
    endfunction

    task check_ref(input [11:0] exp, input [8*44:1] name);
        begin
            checks = checks + 1;
            if ({fault_level, fault_device, fault_code} !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] %0s  t=%b e=%b c=%b mask=%b", name,
                         timeout, error_flag, critical_fault, critical_mask);
                $display("         got {lvl,dev,code} = %0d/%0d/0x%02h",
                         fault_level, fault_device, fault_code);
                $display("         exp {lvl,dev,code} = %0d/%0d/0x%02h",
                         exp[11:10], exp[9:8], exp[7:0]);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // 시나리오 — 번호는 02 문서 8장 필수 Testbench 항목 번호
    //--------------------------------------------------------------------------
    integer k;
    integer tv, ev, cv, mv;

    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        settle;

        $display("=== B01 : 정상 입력 -> Level 0 ===");
        check(LEVEL_0, DEV_MN, F_NONE, "all normal");
        check_int(fault_valid, 1, "fault_valid = 1 when enabled");

        $display("=== B02 : Device 0 Timeout 1회 -> Level 1 ===");
        timeout = 3'b001; settle;
        check(LEVEL_1, DEV0, F_TIMEOUT, "dev0 timeout temporary");
        do_tick;                                 // count=1 (< limit 3)
        check(LEVEL_1, DEV0, F_TIMEOUT, "dev0 timeout after 1 tick");
        check_int(fault_count0, 1, "count0 == 1");

        $display("=== B03 : Device 0 Timeout 지속 -> Level 2 ===");
        do_tick;                                 // count=2
        check(LEVEL_1, DEV0, F_TIMEOUT, "count2 still level1");
        do_tick;                                 // count=3 == limit
        check(LEVEL_2, DEV0, F_TIMEOUT, "dev0 timeout persistent");
        check_int(fault_count0, 3, "count0 == 3");
        clear_inputs; do_tick;

        $display("=== B04 : Device 1 Error -> Level 1 ===");
        error_flag = 3'b010; settle;
        check(LEVEL_1, DEV1, F_ERROR, "dev1 error temporary");
        clear_inputs; do_tick;

        $display("=== B05 : Device 2 Timeout -> Tick 대기 없이 Level 3 ===");
        // CRITICAL_MASK=3'b100 이므로 Device 2 의 Timeout 도 Critical 조건이다
        @(negedge clk); timeout = 3'b100;
        @(posedge clk);                          // 입력 인가 후 첫 클럭
        @(negedge clk);
        check(LEVEL_3, DEV2, F_CRIT, "dev2 timeout -> critical in 1 clk");
        check_int(fault_count2, 0, "no tick consumed");
        clear_inputs; do_tick;

        $display("=== B06 : Device 2 Error -> Tick 대기 없이 Level 3 ===");
        @(negedge clk); error_flag = 3'b100;
        @(posedge clk); @(negedge clk);
        check(LEVEL_3, DEV2, F_CRIT, "dev2 error -> critical in 1 clk");
        clear_inputs; do_tick;

        $display("=== B07 : Device 2 Critical -> Tick 대기 없이 Level 3 ===");
        @(negedge clk); critical_fault = 3'b100;
        @(posedge clk); @(negedge clk);
        check(LEVEL_3, DEV2, F_CRIT, "dev2 critical in 1 clk");
        check_int(fault_count2, 0, "no tick consumed");
        clear_inputs; do_tick;

        $display("=== B08 : Device 0+1 동시 Fault -> Tick 대기 없이 Level 3 Multi ===");
        @(negedge clk); timeout = 3'b001; error_flag = 3'b010;
        @(posedge clk); @(negedge clk);
        check(LEVEL_3, DEV_MN, F_MULTI, "dev0+dev1 multi in 1 clk");
        clear_inputs; do_tick;

        $display("=== B09 : Critical 장치 + 일반 Fault -> Critical 우선 ===");
        timeout = 3'b001; critical_fault = 3'b100; settle;
        check(LEVEL_3, DEV2, F_CRIT, "critical device id beats multi");
        clear_inputs; do_tick;

        $display("=== B10 : 동일 장치 Timeout + Error -> ERROR_CODE ===");
        timeout = 3'b001; error_flag = 3'b001; settle;
        check(LEVEL_1, DEV0, F_ERROR, "same device timeout+error -> ERROR_CODE");
        do_tick; do_tick; do_tick;
        check(LEVEL_2, DEV0, F_ERROR, "persistent keeps ERROR_CODE");
        clear_inputs; do_tick;

        $display("=== B11 : Critical 장치 둘 이상 -> FAULT_CRITICAL, Device 3 ===");
        critical_mask = 3'b111;
        critical_fault = 3'b011; settle;
        check(LEVEL_3, DEV_MN, F_CRIT, "two critical devices -> device 3");
        clear_inputs;
        critical_fault = 3'b001; settle;
        check(LEVEL_3, DEV0, F_CRIT, "one critical device -> its id");
        clear_inputs;
        critical_mask = 3'b100; do_tick;

        $display("=== B12 : Level 1 의 Device/Code 가 현재 원인과 일치 ===");
        error_flag = 3'b010; settle;
        check(LEVEL_1, DEV1, F_ERROR, "level1 dev1 error");
        error_flag = 3'b000; timeout = 3'b010; settle;
        check(LEVEL_1, DEV1, F_TIMEOUT, "level1 dev1 timeout");
        clear_inputs; do_tick;

        $display("=== B13 : 오류 제거 -> Count 0, Level 복귀 ===");
        timeout = 3'b001; settle;
        do_tick; do_tick; do_tick;
        check(LEVEL_2, DEV0, F_TIMEOUT, "persistent before clear");
        clear_inputs;
        check(LEVEL_0, DEV_MN, F_NONE, "fault cleared -> level0 (tick 불필요)");
        do_tick;
        check_int(fault_count0, 0, "count0 cleared on tick");

        $display("=== B14 : Count 는 eval_tick 에서만 증가 ===");
        timeout = 3'b001; settle;
        repeat (50) @(negedge clk);              // Tick 없이 50 클럭
        check_int(fault_count0, 0, "no tick -> count stays 0");
        check(LEVEL_1, DEV0, F_TIMEOUT, "no tick -> stays level1");
        do_tick;
        check_int(fault_count0, 1, "tick -> count 1");
        clear_inputs; do_tick;

        $display("=== B15 : Count Saturation ===");
        timeout = 3'b001; settle;
        for (k = 0; k < 300; k = k + 1) do_tick;
        check_int(fault_count0, 255, "count0 saturates at 255");
        clear_inputs; do_tick;

        $display("=== B16 : persist_limit = 0 은 1 로 간주 ===");
        persist_limit = 8'd0;
        timeout = 3'b001; settle;
        check(LEVEL_1, DEV0, F_TIMEOUT, "limit0 before tick -> level1");
        do_tick;                                 // count=1 >= 1
        check(LEVEL_2, DEV0, F_TIMEOUT, "limit0 after 1 tick -> level2");
        clear_inputs; do_tick;
        persist_limit = 8'd3;

        $display("=== B17/B18 : 변화 Event 발생 / 중복 Event 없음 ===");
        settle;
        event_cnt = 0;
        error_flag = 3'b010; settle;             // level0 -> level1 : Event 1회
        check_int(event_cnt, 1, "event on change");
        repeat (20) @(negedge clk);              // 같은 상태 유지
        check_int(event_cnt, 1, "no repeated event");
        do_tick; do_tick;                        // count 만 올라감, 출력 동일
        check_int(event_cnt, 1, "count change makes no event");
        do_tick;                                 // count=3 -> level2 : Event 1회 추가
        check_int(event_cnt, 2, "event on level 1->2");
        clear_inputs; do_tick;

        $display("=== B19 : Fault 가 남아 있으면 RESET_FAULT 무시 ===");
        timeout = 3'b001; settle;
        do_tick; do_tick; do_tick;               // count=3 -> level2
        check(LEVEL_2, DEV0, F_TIMEOUT, "before reset_fault : level2");
        @(negedge clk); reset_fault_pulse = 1'b1;
        @(negedge clk); reset_fault_pulse = 1'b0;
        settle;
        check_int(fault_count0, 3, "active fault -> count NOT cleared");
        check(LEVEL_2, DEV0, F_TIMEOUT, "active fault -> level stays 2");
        clear_inputs;

        $display("=== B20 : Fault 가 없을 때 RESET_FAULT 가 Count Clear ===");
        // Tick 없이도 지워지는지 본다 (clear_inputs 뒤 Tick 을 주지 않았다)
        check_int(fault_count0, 3, "count kept before reset_fault (no tick)");
        @(negedge clk); reset_fault_pulse = 1'b1;
        @(negedge clk); reset_fault_pulse = 1'b0;
        settle;
        check_int(fault_count0, 0, "no fault -> reset_fault clears count");
        check(LEVEL_0, DEV_MN, F_NONE, "level 0 after reset_fault");

        $display("=== B21 : enable=0 안전 출력 (02 문서 6.2) ===");
        timeout = 3'b001; settle;
        do_tick; do_tick; do_tick;
        check(LEVEL_2, DEV0, F_TIMEOUT, "level2 before disable");
        event_cnt = 0;
        enable = 1'b0; settle;
        check(LEVEL_0, DEV_MN, F_NONE, "disable -> safe output");
        check_int(fault_valid, 0, "fault_valid = 0");
        check_int(fault_count0, 0, "count cleared while disabled");
        check_int(event_cnt, 0, "no IRQ event while disabled");
        do_tick; do_tick; do_tick;
        check_int(fault_count0, 0, "count stays 0 while disabled");
        check(LEVEL_0, DEV_MN, F_NONE, "still safe while disabled");
        enable = 1'b1; settle;
        check(LEVEL_1, DEV0, F_TIMEOUT, "re-enable -> level1 (count restarts)");
        check_int(fault_valid, 1, "fault_valid = 1 again");
        clear_inputs; do_tick;

        $display("=== B22 : 전수 검증 (t/e/c 512조합 x mask 4종 x 지속 2종) ===");
        persist_limit = 8'd1;               // Tick 1회로 지속 성립
        enable = 1'b1;
        for (mv = 0; mv < 4; mv = mv + 1) begin
            case (mv)
                0: critical_mask = 3'b100;  // 기본값
                1: critical_mask = 3'b111;
                2: critical_mask = 3'b000;
                3: critical_mask = 3'b010;
            endcase
            for (tv = 0; tv < 8; tv = tv + 1)
            for (ev = 0; ev < 8; ev = ev + 1)
            for (cv = 0; cv < 8; cv = cv + 1) begin
                // 1) 지속 Count 를 0 으로 만든 뒤 조합 인가 -> phit = 0
                timeout = 3'b000; error_flag = 3'b000; critical_fault = 3'b000;
                do_tick;
                timeout = tv[2:0]; error_flag = ev[2:0]; critical_fault = cv[2:0];
                settle;
                check_ref(ref_out(tv[2:0], ev[2:0], cv[2:0], critical_mask, 3'b000),
                          "exhaustive non-persist");

                // 2) Tick 1회 -> 오류가 있는 모든 장치가 지속 성립
                do_tick;
                check_ref(ref_out(tv[2:0], ev[2:0], cv[2:0], critical_mask,
                                  tv[2:0] | ev[2:0] | cv[2:0]),
                          "exhaustive persist");
            end
        end
        critical_mask = 3'b100;
        persist_limit = 8'd3;
        clear_inputs;
        $display("  전수 검증 완료 (누적 checks=%0d, errors=%0d)", checks, errors);

        $display("");
        $display("=====================================");
        $display(" checks = %0d, errors = %0d  -> %0s", checks, errors,
                 (errors == 0) ? "ALL PASS" : "FAIL");
        $display("=====================================");
        $finish;
    end

endmodule
