`timescale 1ns / 1ps

/*
 * safety_controller_core
 *
 * 시스템 상태
 *   2'b00 : NORMAL
 *   2'b01 : WARNING
 *   2'b10 : DEGRADED
 *   2'b11 : SAFE_MODE
 *
 * 주요 동작 정책
 *   - 현재 Fault Level이 현재 상태보다 높으면 eval_tick을 기다리지 않고
 *     다음 클럭에서 즉시 더 안전한 상태로 전환한다.
 *   - 상태 복구에 필요한 연속 횟수는 eval_tick에서만 증가한다.
 *   - RECOVERY_COUNT 설정값이 0이면 1회로 처리한다.
 *   - SAFE_MODE는 자동 복구하지 않는다.
 *   - SAFE_MODE에서는 유효한 Level 0과 manual_reset_pulse가 동시에
 *     입력된 경우에만 NORMAL로 복구한다.
 *   - enable=0이면 상태와 타이머를 NORMAL 초기 상태로 되돌리고
 *     모든 제어 출력을 차단한다.
 *   - fault_valid=0이면 상태는 유지하지만 복구 횟수를 초기화하고
 *     모든 제어 출력을 안전값으로 차단한다.
 */
module safety_controller_core (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Fault Manager 입력
    input  wire [1:0]  fault_level,
    input  wire [1:0]  fault_device,
    input  wire [7:0]  fault_code,
    input  wire        fault_valid,

    // 설정 및 제어 입력
    input  wire [2:0]  degrade_mask,
    input  wire [15:0] recovery_count_setting,
    input  wire        eval_tick,
    input  wire        manual_reset_pulse,

    // 상태 및 제어 출력
    output wire [1:0]  system_state,
    output reg  [2:0]  output_enable,
    output reg         actuator_enable,
    output reg         control_valid,
    output reg  [31:0] state_timer,
    output reg         state_change_event
);

    // 시스템 상태값
    localparam [1:0] ST_NORMAL    = 2'b00;
    localparam [1:0] ST_WARNING   = 2'b01;
    localparam [1:0] ST_DEGRADED  = 2'b10;
    localparam [1:0] ST_SAFE_MODE = 2'b11;

    reg [1:0] current_state;
    reg [1:0] next_state;

    // 현재까지 연속으로 확인된 복구 조건 횟수
    reg [15:0] recovery_count;
    reg [15:0] next_recovery_count;

    // 복구 조건이 향하는 목표 상태
    reg [1:0] recovery_target;
    reg [1:0] next_recovery_target;

    wire [15:0] effective_recovery_count;

    // 설정값 0은 복구 조건 1회 확인으로 처리한다.
    assign effective_recovery_count =
        (recovery_count_setting == 16'd0)
        ? 16'd1
        : recovery_count_setting;

    assign system_state = current_state;

    /*
     * 다음 상태 및 복구 횟수 계산
     *
     * 우선순위
     *   1. enable=0 초기화
     *   2. SAFE_MODE 수동 복구
     *   3. fault_valid 확인
     *   4. 상태 악화 즉시 반영
     *   5. eval_tick 기반 상태 복구
     */
    always @(*) begin
        next_state           = current_state;
        next_recovery_count  = recovery_count;
        next_recovery_target = recovery_target;

        // Disable 시 상태와 복구 기록을 NORMAL 초기값으로 되돌린다.
        if (!enable) begin
            next_state           = ST_NORMAL;
            next_recovery_count  = 16'd0;
            next_recovery_target = ST_NORMAL;
        end

        /*
         * SAFE_MODE는 자동 복구하지 않는다.
         * 유효한 Level 0 상태에서 수동 복구 명령이 들어온 경우만 허용한다.
         */
        else if (current_state == ST_SAFE_MODE) begin
            next_recovery_count  = 16'd0;
            next_recovery_target = ST_SAFE_MODE;

            if (manual_reset_pulse &&
                fault_valid &&
                (fault_level == 2'd0)) begin
                next_state           = ST_NORMAL;
                next_recovery_target = ST_NORMAL;
            end
        end

        /*
         * Fault 정보가 유효하지 않으면 현재 상태를 유지하고,
         * 진행 중이던 복구 판정은 취소한다.
         */
        else if (!fault_valid) begin
            next_recovery_count  = 16'd0;
            next_recovery_target = current_state;
        end

        else begin
            case (current_state)
                ST_NORMAL: begin
                    // NORMAL에서는 모든 Fault 상태가 상태 악화이므로 즉시 반영한다.
                    next_recovery_count  = 16'd0;
                    next_recovery_target = ST_NORMAL;

                    case (fault_level)
                        2'd0: next_state = ST_NORMAL;
                        2'd1: next_state = ST_WARNING;
                        2'd2: next_state = ST_DEGRADED;
                        2'd3: next_state = ST_SAFE_MODE;
                        default: next_state = ST_SAFE_MODE;
                    endcase
                end

                ST_WARNING: begin
                    // Level 2와 Level 3은 eval_tick 없이 즉시 상태를 악화시킨다.
                    if (fault_level == 2'd3) begin
                        next_state           = ST_SAFE_MODE;
                        next_recovery_count  = 16'd0;
                        next_recovery_target = ST_SAFE_MODE;
                    end
                    else if (fault_level == 2'd2) begin
                        next_state           = ST_DEGRADED;
                        next_recovery_count  = 16'd0;
                        next_recovery_target = ST_DEGRADED;
                    end
                    else if (fault_level == 2'd1) begin
                        next_recovery_count  = 16'd0;
                        next_recovery_target = ST_WARNING;
                    end
                    else begin
                        /*
                         * Level 0이 RECOVERY_COUNT 횟수만큼 연속 확인되면
                         * NORMAL로 복구한다. 횟수는 eval_tick에서만 증가한다.
                         */
                        next_recovery_target = ST_NORMAL;

                        if (recovery_target != ST_NORMAL) begin
                            next_recovery_count = 16'd0;
                        end

                        if (eval_tick) begin
                            if (effective_recovery_count == 16'd1) begin
                                next_state           = ST_NORMAL;
                                next_recovery_count  = 16'd0;
                                next_recovery_target = ST_NORMAL;
                            end
                            else if (recovery_target != ST_NORMAL) begin
                                next_recovery_count = 16'd1;
                            end
                            else if (recovery_count >=
                                     (effective_recovery_count - 16'd1)) begin
                                next_state           = ST_NORMAL;
                                next_recovery_count  = 16'd0;
                                next_recovery_target = ST_NORMAL;
                            end
                            else begin
                                next_recovery_count =
                                    recovery_count + 16'd1;
                            end
                        end
                    end
                end

                ST_DEGRADED: begin
                    // Level 3은 eval_tick 없이 즉시 SAFE_MODE로 전환한다.
                    if (fault_level == 2'd3) begin
                        next_state           = ST_SAFE_MODE;
                        next_recovery_count  = 16'd0;
                        next_recovery_target = ST_SAFE_MODE;
                    end
                    else if (fault_level == 2'd2) begin
                        next_recovery_count  = 16'd0;
                        next_recovery_target = ST_DEGRADED;
                    end
                    else if (fault_level == 2'd1) begin
                        /*
                         * Level 1이 RECOVERY_COUNT 횟수만큼 연속 확인되면
                         * WARNING으로 복구한다.
                         */
                        next_recovery_target = ST_WARNING;

                        if (recovery_target != ST_WARNING) begin
                            next_recovery_count = 16'd0;
                        end

                        if (eval_tick) begin
                            if (effective_recovery_count == 16'd1) begin
                                next_state           = ST_WARNING;
                                next_recovery_count  = 16'd0;
                                next_recovery_target = ST_WARNING;
                            end
                            else if (recovery_target != ST_WARNING) begin
                                next_recovery_count = 16'd1;
                            end
                            else if (recovery_count >=
                                     (effective_recovery_count - 16'd1)) begin
                                next_state           = ST_WARNING;
                                next_recovery_count  = 16'd0;
                                next_recovery_target = ST_WARNING;
                            end
                            else begin
                                next_recovery_count =
                                    recovery_count + 16'd1;
                            end
                        end
                    end
                    else begin
                        /*
                         * Level 0이 RECOVERY_COUNT 횟수만큼 연속 확인되면
                         * NORMAL로 직접 복구한다.
                         */
                        next_recovery_target = ST_NORMAL;

                        if (recovery_target != ST_NORMAL) begin
                            next_recovery_count = 16'd0;
                        end

                        if (eval_tick) begin
                            if (effective_recovery_count == 16'd1) begin
                                next_state           = ST_NORMAL;
                                next_recovery_count  = 16'd0;
                                next_recovery_target = ST_NORMAL;
                            end
                            else if (recovery_target != ST_NORMAL) begin
                                next_recovery_count = 16'd1;
                            end
                            else if (recovery_count >=
                                     (effective_recovery_count - 16'd1)) begin
                                next_state           = ST_NORMAL;
                                next_recovery_count  = 16'd0;
                                next_recovery_target = ST_NORMAL;
                            end
                            else begin
                                next_recovery_count =
                                    recovery_count + 16'd1;
                            end
                        end
                    end
                end

                default: begin
                    // 정의되지 않은 상태값은 안전을 위해 SAFE_MODE로 보낸다.
                    next_state           = ST_SAFE_MODE;
                    next_recovery_count  = 16'd0;
                    next_recovery_target = ST_SAFE_MODE;
                end
            endcase
        end
    end

    // 상태, 복구 기록, 상태 타이머 및 상태 변경 이벤트 저장
    always @(posedge clk) begin
        if (reset) begin
            current_state      <= ST_NORMAL;
            recovery_count     <= 16'd0;
            recovery_target    <= ST_NORMAL;
            state_timer        <= 32'd0;
            state_change_event <= 1'b0;
        end
        else if (!enable) begin
            /*
             * Disable 정책
             *   - 상태는 NORMAL
             *   - 상태 유지 타이머는 0
             *   - 상태 변경 이벤트는 발생시키지 않음
             */
            current_state      <= ST_NORMAL;
            recovery_count     <= 16'd0;
            recovery_target    <= ST_NORMAL;
            state_timer        <= 32'd0;
            state_change_event <= 1'b0;
        end
        else begin
            current_state   <= next_state;
            recovery_count  <= next_recovery_count;
            recovery_target <= next_recovery_target;

            // 실제 상태가 바뀌는 클럭에만 1클럭 펄스를 출력한다.
            state_change_event <= (current_state != next_state);

            /*
             * 상태가 바뀌면 0으로 초기화하고,
             * 같은 상태를 유지하면 최대값까지 포화 증가한다.
             */
            if (current_state != next_state) begin
                state_timer <= 32'd0;
            end
            else if (state_timer != 32'hFFFF_FFFF) begin
                state_timer <= state_timer + 32'd1;
            end
        end
    end

    /*
     * 상태별 출력 제어
     *
     * fault_valid=0이면 Fault 정보가 유효하지 않으므로 현재 상태와 관계없이
     * 출력은 안전값으로 차단한다.
     */
    always @(*) begin
        output_enable   = 3'b000;
        actuator_enable = 1'b0;
        control_valid   = 1'b0;

        if (enable && fault_valid) begin
            case (current_state)
                ST_NORMAL: begin
                    output_enable   = 3'b111;
                    actuator_enable = 1'b1;
                    control_valid   = 1'b1;
                end

                ST_WARNING: begin
                    output_enable   = 3'b111;
                    actuator_enable = 1'b1;
                    control_valid   = 1'b1;
                end

                ST_DEGRADED: begin
                    /*
                     * 단일 Fault는 해당 장치만 차단한다.
                     * fault_device=3은 다중 장치 또는 특정 장치 없음이므로
                     * AXI에서 설정한 degrade_mask를 적용한다.
                     */
                    case (fault_device)
                        2'd0: output_enable = 3'b110;
                        2'd1: output_enable = 3'b101;
                        2'd2: output_enable = 3'b011;
                        default:
                            output_enable = 3'b111 & ~degrade_mask;
                    endcase

                    actuator_enable = 1'b1;
                    control_valid   = 1'b1;
                end

                ST_SAFE_MODE: begin
                    output_enable   = 3'b000;
                    actuator_enable = 1'b0;
                    control_valid   = 1'b0;
                end

                default: begin
                    output_enable   = 3'b000;
                    actuator_enable = 1'b0;
                    control_valid   = 1'b0;
                end
            endcase
        end
    end

    /*
     * fault_code는 상태 전환이 아니라 AXI 상태 확인과 로그에서 사용한다.
     * 이 Core의 상태 전환은 fault_level과 fault_valid를 기준으로 수행한다.
     */

endmodule