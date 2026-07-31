`timescale 1ns / 1ps
`default_nettype none

/*
 * safety_controller_core 테스트벤치
 *
 * 검증 항목
 *   1. Reset 후 NORMAL 초기화
 *   2. 상태 악화 시 eval_tick 없이 즉시 전환
 *   3. RECOVERY_COUNT 횟수만큼 연속 확인 후 복구
 *   4. DEGRADED 상태의 fault_device별 출력 차단
 *   5. SAFE_MODE 자동 복구 금지 및 Manual Reset 조건
 *   6. fault_valid=0일 때 상태 유지 및 출력 차단
 *   7. enable=0일 때 NORMAL 초기화 및 출력 차단
 *   8. RECOVERY_COUNT=0을 1회로 처리
 */
module tb_safety_controller_core;

    // 시스템 상태값
    localparam [1:0] ST_NORMAL    = 2'b00;
    localparam [1:0] ST_WARNING   = 2'b01;
    localparam [1:0] ST_DEGRADED  = 2'b10;
    localparam [1:0] ST_SAFE_MODE = 2'b11;

    reg         clk;
    reg         reset;
    reg         enable;

    reg  [1:0]  fault_level;
    reg  [1:0]  fault_device;
    reg  [7:0]  fault_code;
    reg         fault_valid;

    reg  [2:0]  degrade_mask;
    reg  [15:0] recovery_count_setting;
    reg         eval_tick;
    reg         manual_reset_pulse;

    wire [1:0]  system_state;
    wire [2:0]  output_enable;
    wire        actuator_enable;
    wire        control_valid;
    wire [31:0] state_timer;
    wire        state_change_event;

    integer test_count;
    integer error_count;

    // 검증 대상 Core 인스턴스
    safety_controller_core dut (
        .clk                    (clk),
        .reset                  (reset),
        .enable                 (enable),

        .fault_level            (fault_level),
        .fault_device           (fault_device),
        .fault_code             (fault_code),
        .fault_valid            (fault_valid),

        .degrade_mask           (degrade_mask),
        .recovery_count_setting (recovery_count_setting),
        .eval_tick              (eval_tick),
        .manual_reset_pulse     (manual_reset_pulse),

        .system_state           (system_state),
        .output_enable          (output_enable),
        .actuator_enable        (actuator_enable),
        .control_valid          (control_valid),
        .state_timer            (state_timer),
        .state_change_event     (state_change_event)
    );

    // 100 MHz 클럭 생성
    always #5 clk = ~clk;

    /*
     * Fault 입력 후 eval_tick 없이 다음 클럭까지 진행한다.
     * 상태 악화가 즉시 반영되는지 확인할 때 사용한다.
     */
    task apply_fault_immediate;
        input [1:0] level;
        input [1:0] device;
        begin
            @(negedge clk);
            fault_level  = level;
            fault_device = device;
            fault_valid  = 1'b1;
            eval_tick    = 1'b0;

            @(posedge clk);
            #1;
        end
    endtask

    // 복구 판정용 eval_tick을 한 클럭 동안 발생시킨다.
    task apply_eval_tick;
        input [1:0] level;
        begin
            @(negedge clk);
            fault_level = level;
            fault_valid = 1'b1;
            eval_tick   = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            eval_tick = 1'b0;
            #1;
        end
    endtask

    // Manual Reset을 한 클럭 동안 발생시킨다.
    task apply_manual_reset;
        begin
            @(negedge clk);
            manual_reset_pulse = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            manual_reset_pulse = 1'b0;
            #1;
        end
    endtask

    // 현재 상태를 기대값과 비교한다.
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

    // 현재 출력 정책을 기대값과 비교한다.
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

    // 내부 복구 카운터를 기대값과 비교한다.
    task check_recovery_count;
        input [15:0] expected_count;
        begin
            test_count = test_count + 1;

            if (dut.recovery_count !== expected_count) begin
                error_count = error_count + 1;
                $display(
                    "[FAIL %0d] 복구 카운트 기대값=%0d, 실제값=%0d, 시간=%0t",
                    test_count,
                    expected_count,
                    dut.recovery_count,
                    $time
                );
            end
            else begin
                $display(
                    "[PASS %0d] 복구 카운트=%0d, 시간=%0t",
                    test_count,
                    dut.recovery_count,
                    $time
                );
            end
        end
    endtask

    // 1비트 신호를 기대값과 비교한다.
    task check_bit;
        input actual_value;
        input expected_value;
        begin
            test_count = test_count + 1;

            if (actual_value !== expected_value) begin
                error_count = error_count + 1;
                $display(
                    "[FAIL %0d] 1비트 신호 기대값=%b, 실제값=%b, 시간=%0t",
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

    initial begin
        clk                    = 1'b0;
        reset                  = 1'b1;
        enable                 = 1'b0;

        fault_level            = 2'd0;
        fault_device           = 2'd0;
        fault_code             = 8'd0;
        fault_valid            = 1'b1;

        degrade_mask           = 3'b001;
        recovery_count_setting = 16'd3;
        eval_tick              = 1'b0;
        manual_reset_pulse     = 1'b0;

        test_count             = 0;
        error_count            = 0;

        // Reset을 충분히 유지한다.
        repeat (3) @(posedge clk);

        @(negedge clk);
        reset  = 1'b0;
        enable = 1'b1;

        @(posedge clk);
        #1;

        // T1: Reset 해제 후 NORMAL 및 정상 출력
        $display("\n[T1] Reset 후 NORMAL 초기화");
        check_state(ST_NORMAL);
        check_outputs(3'b111, 1'b1, 1'b1);

        /*
         * T2: Level 1은 NORMAL보다 높은 상태이므로
         * eval_tick 없이 다음 클럭에 WARNING으로 전환되어야 한다.
         */
        $display("\n[T2] Level 1 즉시 WARNING 전환");
        apply_fault_immediate(2'd1, 2'd0);
        check_state(ST_WARNING);
        check_bit(state_change_event, 1'b1);
        check_outputs(3'b111, 1'b1, 1'b1);

        // 상태 변경 이벤트는 한 클럭 후 0으로 내려가야 한다.
        @(posedge clk);
        #1;
        check_bit(state_change_event, 1'b0);

        /*
         * T3: fault_level만 0으로 바꾸고 eval_tick을 주지 않으면
         * 복구 카운터와 상태가 변하지 않아야 한다.
         */
        $display("\n[T3] eval_tick 없는 복구 금지");
        @(negedge clk);
        fault_level = 2'd0;
        eval_tick   = 1'b0;

        repeat (2) @(posedge clk);
        #1;
        check_state(ST_WARNING);
        check_recovery_count(16'd0);

        /*
         * T4: Level 0을 세 번 연속 평가하면
         * WARNING에서 NORMAL로 복구되어야 한다.
         */
        $display("\n[T4] Recovery Count 3회 후 NORMAL 복구");
        apply_eval_tick(2'd0);
        check_state(ST_WARNING);
        check_recovery_count(16'd1);

        apply_eval_tick(2'd0);
        check_state(ST_WARNING);
        check_recovery_count(16'd2);

        apply_eval_tick(2'd0);
        check_state(ST_NORMAL);
        check_recovery_count(16'd0);
        check_bit(state_change_event, 1'b1);

        /*
         * T5: Level 2는 eval_tick 없이 DEGRADED로 즉시 전환되어야 한다.
         * fault_device=0이면 Device 0만 차단되어 출력은 110이다.
         */
        $display("\n[T5] Level 2 즉시 DEGRADED 전환");
        apply_fault_immediate(2'd2, 2'd0);
        check_state(ST_DEGRADED);
        check_outputs(3'b110, 1'b1, 1'b1);

        // DEGRADED 상태에서 Fault Device별 출력 차단 정책을 확인한다.
        $display("\n[T6] DEGRADED 장치별 출력 정책");
        @(negedge clk);
        fault_device = 2'd1;
        #1;
        check_outputs(3'b101, 1'b1, 1'b1);

        fault_device = 2'd2;
        #1;
        check_outputs(3'b011, 1'b1, 1'b1);

        fault_device = 2'd3;
        degrade_mask = 3'b101;
        #1;
        check_outputs(3'b010, 1'b1, 1'b1);

        /*
         * T7: DEGRADED에서 Level 1이 세 번 연속 확인되면
         * WARNING으로 단계 복구되어야 한다.
         */
        $display("\n[T7] DEGRADED에서 WARNING으로 복구");
        apply_eval_tick(2'd1);
        check_state(ST_DEGRADED);
        check_recovery_count(16'd1);

        apply_eval_tick(2'd1);
        check_state(ST_DEGRADED);
        check_recovery_count(16'd2);

        apply_eval_tick(2'd1);
        check_state(ST_WARNING);
        check_recovery_count(16'd0);

        /*
         * T8: WARNING 상태에서 Level 3은 eval_tick 없이
         * SAFE_MODE로 즉시 전환되어야 한다.
         */
        $display("\n[T8] Level 3 즉시 SAFE_MODE 전환");
        apply_fault_immediate(2'd3, 2'd2);
        check_state(ST_SAFE_MODE);
        check_outputs(3'b000, 1'b0, 1'b0);

        // Fault가 남아 있으면 Manual Reset을 거부해야 한다.
        $display("\n[T9] Fault 잔류 시 Manual Reset 거부");
        fault_level = 2'd1;
        apply_manual_reset();
        check_state(ST_SAFE_MODE);

        /*
         * Fault를 제거하고 eval_tick을 여러 번 입력해도
         * SAFE_MODE는 자동으로 복구되면 안 된다.
         */
        $display("\n[T10] SAFE_MODE 자동 복구 금지");
        apply_eval_tick(2'd0);
        apply_eval_tick(2'd0);
        apply_eval_tick(2'd0);
        check_state(ST_SAFE_MODE);

        // Level 0에서 Manual Reset이 들어오면 NORMAL로 복구해야 한다.
        $display("\n[T11] Level 0 + Manual Reset으로 NORMAL 복구");
        apply_manual_reset();
        check_state(ST_NORMAL);
        check_outputs(3'b111, 1'b1, 1'b1);

        /*
         * T12: fault_valid=0이면 상태를 유지하지만
         * 모든 제어 출력은 안전값으로 차단해야 한다.
         */
        $display("\n[T12] fault_valid=0 안전 출력");
        apply_fault_immediate(2'd1, 2'd0);
        check_state(ST_WARNING);

        @(negedge clk);
        fault_valid = 1'b0;
        fault_level = 2'd0;

        @(posedge clk);
        #1;
        check_state(ST_WARNING);
        check_recovery_count(16'd0);
        check_outputs(3'b000, 1'b0, 1'b0);

        /*
         * T13: enable=0이면 다음 클럭에서 NORMAL로 초기화되고
         * 타이머와 이벤트는 0, 모든 출력은 차단되어야 한다.
         */
        $display("\n[T13] Disable 정책");
        @(negedge clk);
        enable = 1'b0;

        @(posedge clk);
        #1;
        check_state(ST_NORMAL);
        check_outputs(3'b000, 1'b0, 1'b0);
        check_bit(state_change_event, 1'b0);

        test_count = test_count + 1;
        if (state_timer !== 32'd0) begin
            error_count = error_count + 1;
            $display(
                "[FAIL %0d] Disable 상태 타이머 기대값=0, 실제값=%0d, 시간=%0t",
                test_count,
                state_timer,
                $time
            );
        end
        else begin
            $display(
                "[PASS %0d] Disable 상태 타이머=0, 시간=%0t",
                test_count,
                $time
            );
        end

        /*
         * T14: recovery_count_setting=0은 1회로 처리되어야 한다.
         * 다시 Enable한 뒤 WARNING 진입 후 한 번의 eval_tick으로 복구한다.
         */
        $display("\n[T14] Recovery Count 설정값 0 처리");
        @(negedge clk);
        enable                 = 1'b1;
        fault_valid            = 1'b1;
        fault_level            = 2'd0;
        recovery_count_setting = 16'd0;

        @(posedge clk);
        #1;
        check_state(ST_NORMAL);

        apply_fault_immediate(2'd1, 2'd0);
        check_state(ST_WARNING);

        apply_eval_tick(2'd0);
        check_state(ST_NORMAL);
        check_recovery_count(16'd0);

        // 전체 테스트 결과 출력
        if (error_count == 0) begin
            $display(
                "\n========================================"
            );
            $display(
                "ALL TESTS PASSED: 총 %0d개 검증 통과",
                test_count
            );
            $display(
                "========================================\n"
            );
        end
        else begin
            $display(
                "\n========================================"
            );
            $display(
                "TEST FAILED: 총 %0d개 중 %0d개 실패",
                test_count,
                error_count
            );
            $display(
                "========================================\n"
            );
        end

        $finish;
    end

endmodule

`default_nettype wire
