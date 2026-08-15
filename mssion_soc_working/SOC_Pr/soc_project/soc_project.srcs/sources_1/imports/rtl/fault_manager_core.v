`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 파일   : fault_manager_core.v
// 담당   : 팀원 B (fault_manager_ip)
// 역할   : 오류를 "감지"하는 IP가 아니라, 들어온 오류를 중요도와 지속 횟수에 따라
//          Fault Level 0~3 으로 등급화하는 IP.
//
// 근거 문서
//   00_TEAM_COMMON_SPEC  5.2(공통 eval_tick), 7장(상태/코드 정의), 10장(Fault 정책),
//                        12.1(Disable 안전 출력)
//   02_MEMBER_B          2장(포트), 3장(우선순위), 4장(지속 Count), 5장(Device 선택),
//                        6.1(RESET_FAULT), 6.2(Disable 출력)
//
// 우선순위 (높은 것이 낮은 것을 덮어쓴다) — 00 문서 10장
//   device_fault       = timeout | error_flag | critical_fault
//   critical_condition = |(device_fault & critical_mask)
//
//   P1 Critical      : critical_condition != 0        -> Level 3, FAULT_CRITICAL
//   P2 다중 장치     : device_fault 비트 2개 이상     -> Level 3, FAULT_MULTI_DEVICE
//   P3 지속 일반오류 : persist_cnt >= PERSIST_LIMIT   -> Level 2
//   P4 일시 일반오류 : device_fault 존재              -> Level 1
//   P5 정상                                            -> Level 0, FAULT_NONE
//
//   critical_mask 는 critical_fault 입력에만 걸리는 Mask 가 아니다. Mask 된 장치의
//   Timeout / Error / Critical Fault 를 모두 Critical 조건으로 처리한다 (02 문서 3장).
//
// 지속 Count 는 100MHz 매 클럭이 아니라 공통 eval_tick 에서만 갱신한다 (00 문서 5.2).
// Critical 조건과 다중 장치 Fault 는 eval_tick 과 무관하게 매 클럭 판정한다.
//////////////////////////////////////////////////////////////////////////////////

module fault_manager_core (
    input  wire       clk,
    input  wire       reset,              // active high (= ~S_AXI_ARESETN)
    input  wire       enable,             // CTRL.bit0
    input  wire       eval_tick,          // 공통 eval_tick_generator 출력 (1클럭 펄스)

    input  wire [2:0] timeout,            // heartbeat_monitor_ip 로부터
    input  wire [2:0] error_flag,         // 외부/Simulator
    input  wire [2:0] critical_fault,     // 외부/Simulator
    input  wire [2:0] critical_mask,      // CRITICAL_MASK 레지스터, 기본 3'b100
    input  wire [7:0] persist_limit,      // PERSIST_LIMIT 레지스터
    input  wire       reset_fault_pulse,  // CTRL.bit1 (W1P)

    output reg  [1:0] fault_level,
    output reg  [1:0] fault_device,
    output reg  [7:0] fault_code,
    output reg        fault_valid,
    output wire [7:0] fault_count0,
    output wire [7:0] fault_count1,
    output wire [7:0] fault_count2,
    output reg        fault_change_event  // level/device/code 중 하나라도 바뀌는 1클럭 펄스
);

    //--------------------------------------------------------------------------
    // 공통 명세 7장 인코딩 (Magic number 금지, 폭 변경 금지)
    //--------------------------------------------------------------------------
    localparam [1:0] LEVEL_0_NORMAL   = 2'b00,
                     LEVEL_1_WARNING  = 2'b01,
                     LEVEL_2_DEGRADED = 2'b10,
                     LEVEL_3_SAFE     = 2'b11;

    localparam [7:0] FAULT_NONE       = 8'h00,
                     FAULT_TIMEOUT    = 8'h01,
                     FAULT_ERROR_CODE = 8'h02,
                     FAULT_CRITICAL   = 8'h03,
                     FAULT_MULTI_DEVICE = 8'h04;

    localparam [1:0] DEVICE_0          = 2'b00,
                     DEVICE_1          = 2'b01,
                     DEVICE_2          = 2'b10,
                     MULTIPLE_OR_NONE  = 2'b11;

    localparam [7:0] COUNT_MAX = 8'hFF;   // Saturation

    //--------------------------------------------------------------------------
    // 입력 조합
    //--------------------------------------------------------------------------
    // 장치별 현재 오류 (00 문서 10장, 02 문서 4장)
    wire [2:0] device_fault = timeout | error_flag | critical_fault;

    // Critical 조건. Mask 된 장치의 "모든" Fault 원인이 대상이다.
    wire [2:0] crit_active  = device_fault & critical_mask;

    // Mask 밖 장치의 error_flag / critical_fault 는 FAULT_ERROR_CODE 로 취급한다.
    wire [2:0] err_like     = error_flag | critical_fault;

    // persist_limit == 0 은 1로 간주한다 (00 문서 10장, 02 문서 4장)
    wire [7:0] persist_eff  = (persist_limit == 8'd0) ? 8'd1 : persist_limit;

    wire [1:0] fault_num = {1'b0, device_fault[0]} + {1'b0, device_fault[1]}
                         + {1'b0, device_fault[2]};
    wire [1:0] crit_num  = {1'b0, crit_active[0]} + {1'b0, crit_active[1]}
                         + {1'b0, crit_active[2]};

    //--------------------------------------------------------------------------
    // 장치별 지속 Count
    //   - eval_tick 인 클럭에만 갱신
    //   - 오류가 없으면 0, 있으면 +1, 0xFF 에서 Saturation
    //   - enable=0 이면 0 (02 문서 6.2)
    //   - RESET_FAULT 는 현재 Fault 가 하나도 없을 때만 적용한다 (02 문서 6.1).
    //     활성 Fault 가 남아 있는데 Count 만 지워 Level 2 를 Level 1 로 낮추는
    //     동작은 금지되어 있다.
    //--------------------------------------------------------------------------
    wire reset_fault_ok = reset_fault_pulse && (device_fault == 3'b000);

    reg [7:0] persist_cnt [0:2];
    integer   i;

    always @(posedge clk) begin
        if (reset || !enable) begin
            for (i = 0; i < 3; i = i + 1) persist_cnt[i] <= 8'd0;
        end
        else if (reset_fault_ok) begin
            for (i = 0; i < 3; i = i + 1) persist_cnt[i] <= 8'd0;
        end
        else if (eval_tick) begin
            for (i = 0; i < 3; i = i + 1) begin
                if (device_fault[i]) begin
                    if (persist_cnt[i] != COUNT_MAX) persist_cnt[i] <= persist_cnt[i] + 8'd1;
                end
                else persist_cnt[i] <= 8'd0;
            end
        end
    end

    assign fault_count0 = persist_cnt[0];
    assign fault_count1 = persist_cnt[1];
    assign fault_count2 = persist_cnt[2];

    // 지속 판정. 현재도 오류가 살아 있어야 성립하므로, 오류가 사라지면
    // 다음 Tick 을 기다리지 않고 바로 하위 우선순위로 내려간다.
    wire [2:0] persist_hit = {
        (device_fault[2] && (persist_cnt[2] >= persist_eff)),
        (device_fault[1] && (persist_cnt[1] >= persist_eff)),
        (device_fault[0] && (persist_cnt[0] >= persist_eff))
    };

    //--------------------------------------------------------------------------
    // Device 선택 (02 문서 5장)
    //--------------------------------------------------------------------------
    // P3/P4 에서는 P2 가 이미 걸러졌으므로 오류 장치가 정확히 1개다.
    reg [1:0] single_dev;
    always @* begin
        single_dev = MULTIPLE_OR_NONE;
        if      (device_fault[0]) single_dev = DEVICE_0;
        else if (device_fault[1]) single_dev = DEVICE_1;
        else if (device_fault[2]) single_dev = DEVICE_2;
    end

    // Critical 조건 장치가 둘 이상이면 특정할 수 없으므로 MULTIPLE_OR_NONE
    reg [1:0] crit_dev;
    always @* begin
        crit_dev = MULTIPLE_OR_NONE;
        if (crit_num == 2'd1) begin
            if      (crit_active[0]) crit_dev = DEVICE_0;
            else if (crit_active[1]) crit_dev = DEVICE_1;
            else                     crit_dev = DEVICE_2;
        end
    end

    // 단일 오류 장치의 Fault Code.
    // 00 문서 10장 : 같은 단일 장치에 Timeout 과 Error 가 동시에 있으면 ERROR_CODE.
    // Mask 밖의 critical_fault 도 ERROR_CODE 로 본다.
    reg [7:0] single_code;
    always @* begin
        single_code = FAULT_NONE;
        case (single_dev)
            DEVICE_0: single_code = err_like[0] ? FAULT_ERROR_CODE : FAULT_TIMEOUT;
            DEVICE_1: single_code = err_like[1] ? FAULT_ERROR_CODE : FAULT_TIMEOUT;
            DEVICE_2: single_code = err_like[2] ? FAULT_ERROR_CODE : FAULT_TIMEOUT;
            default:  single_code = FAULT_NONE;
        endcase
    end

    //--------------------------------------------------------------------------
    // 우선순위 판정 (조합). 기본값을 먼저 할당해 Latch 를 막는다 (공통 명세 5.5)
    //--------------------------------------------------------------------------
    reg [1:0] nxt_level;
    reg [1:0] nxt_device;
    reg [7:0] nxt_code;

    always @* begin
        nxt_level  = LEVEL_0_NORMAL;
        nxt_device = MULTIPLE_OR_NONE;
        nxt_code   = FAULT_NONE;

        if (crit_active != 3'b000) begin                 // P1 Critical
            nxt_level  = LEVEL_3_SAFE;
            nxt_code   = FAULT_CRITICAL;
            nxt_device = crit_dev;
        end
        else if (fault_num >= 2'd2) begin                // P2 다중 장치
            nxt_level  = LEVEL_3_SAFE;
            nxt_code   = FAULT_MULTI_DEVICE;
            nxt_device = MULTIPLE_OR_NONE;
        end
        else if (persist_hit != 3'b000) begin            // P3 지속 일반 오류
            nxt_level  = LEVEL_2_DEGRADED;
            nxt_code   = single_code;
            nxt_device = single_dev;
        end
        else if (device_fault != 3'b000) begin           // P4 일시 일반 오류
            nxt_level  = LEVEL_1_WARNING;
            nxt_code   = single_code;
            nxt_device = single_dev;
        end
    end

    //--------------------------------------------------------------------------
    // 출력 등록 및 변화 Event
    //   - 출력은 Pulse 가 아니라 상태값 (공통 명세 8.5)
    //   - 같은 값이 유지되는 동안에는 Event 를 반복 Set 하지 않는다 (02 문서 7장)
    //   - enable=0 이면 안전값을 강제 출력하고 Event 를 만들지 않는다 (02 문서 6.2,
    //     공통 명세 12.1)
    //--------------------------------------------------------------------------
    wire out_changed = ({nxt_level, nxt_device, nxt_code}
                     != {fault_level, fault_device, fault_code});

    always @(posedge clk) begin
        if (reset) begin
            fault_level        <= LEVEL_0_NORMAL;
            fault_device       <= MULTIPLE_OR_NONE;
            fault_code         <= FAULT_NONE;
            fault_valid        <= 1'b0;
            fault_change_event <= 1'b0;
        end
        else begin
            fault_change_event <= 1'b0;
            fault_valid        <= enable;

            if (enable) begin
                if (out_changed) fault_change_event <= 1'b1;
                fault_level  <= nxt_level;
                fault_device <= nxt_device;
                fault_code   <= nxt_code;
            end
            else begin
                // Disable 안전 출력. 새로운 IRQ Pending 을 만들지 않는다.
                fault_level  <= LEVEL_0_NORMAL;
                fault_device <= MULTIPLE_OR_NONE;
                fault_code   <= FAULT_NONE;
            end
        end
    end

endmodule
