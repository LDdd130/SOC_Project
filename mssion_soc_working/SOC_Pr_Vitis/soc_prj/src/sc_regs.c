/******************************************************************************
 * sc_regs.c — safety_controller_ip 드라이버  (팀원 C 담당 함수)
 *
 * 근거 : 00 공통명세 8.5(B->C), 8.6(출력 정책), 9.3(레지스터 맵),
 *        11장(Safety FSM), 11.1(Recovery 정책), 12.1(Disable 정책)
 *
 * CTRL Shadow 가 필요한 이유
 *   RTL 의 CTRL Write 는 다음과 같다.
 *     if (wstrb_hold[0]) begin
 *         reg_enable <= wdata_hold[0];
 *         if (wdata_hold[1]) manual_reset_pulse <= 1'b1;
 *     end
 *   MANUAL_RESET 을 쏘려고 0x2 만 쓰면 ENABLE 이 0 이 되어 IP 가 꺼진다.
 *   그러면 00 공통명세 12.1 에 따라 출력이 안전값으로 강제되고 복구가 실패한다.
 *   반드시 ENABLE 을 함께 실어 0x3 으로 써야 한다.
 ******************************************************************************/

#include "mission_ip_regs.h"

static u32 s_sc_ctrl = 0;   /* RW 비트(ENABLE)만 보관 */

void SC_Init(u32 degrade_mask, u32 recovery_count)
{
    s_sc_ctrl = 0;
    REG_WR(SC_BASE, SC_CTRL, s_sc_ctrl);                    /* 04 6장 1단계 */

    REG_WR(SC_BASE, SC_IRQ_EN, 0);                          /* 04 6장 2단계 */
    REG_WR(SC_BASE, SC_RECOVERY_COUNT, recovery_count & 0xFFFFu); /* 6단계 */
    REG_WR(SC_BASE, SC_DEGRADE_MASK, degrade_mask & 0x7u);        /* 7단계 */

    REG_WR(SC_BASE, SC_IRQ_STATUS, SC_IRQ_STATE_CHANGE);    /* 04 6장 8단계 */
}

void SC_Enable(int on)
{
    if (on) s_sc_ctrl |=  SC_CTRL_ENABLE;
    else    s_sc_ctrl &= ~SC_CTRL_ENABLE;
    REG_WR(SC_BASE, SC_CTRL, s_sc_ctrl);
}

/*
 * W1P. IP 는 SAFE_MODE 이고 fault_valid=1 이고 fault_level=0 일 때만 받아준다
 * (00 공통명세 11장 / C 의 core 코드 확인함). 그 밖에는 조용히 무시된다.
 * 호출 쪽에서 조건을 먼저 확인하고 $ERR 로 알려주는 것이 프로토콜 규칙이다.
 */
void SC_ManualReset(void)
{
    REG_WR(SC_BASE, SC_CTRL, s_sc_ctrl | SC_CTRL_MANUAL_RESET);
}

void SC_SetDegradeMask(u32 mask)
{
    REG_WR(SC_BASE, SC_DEGRADE_MASK, mask & 0x7u);
}

void SC_SetRecoveryCount(u32 value)
{
    REG_WR(SC_BASE, SC_RECOVERY_COUNT, value & 0xFFFFu);
}

void SC_EnableIrq(int on)
{
    REG_WR(SC_BASE, SC_IRQ_EN, on ? SC_IRQ_STATE_CHANGE : 0u);
}

u32 SC_ReadIrqStatus(void)
{
    return REG_RD(SC_BASE, SC_IRQ_STATUS) & SC_IRQ_STATE_CHANGE;
}

u32 SC_ReadIrqEn(void)
{
    return REG_RD(SC_BASE, SC_IRQ_EN) & SC_IRQ_STATE_CHANGE;
}

void SC_ClearIrq(u32 mask)
{
    REG_WR(SC_BASE, SC_IRQ_STATUS, mask);
}

void SC_ReadStatus(sc_status_t *s)
{
    s->state         = (u8)(REG_RD(SC_BASE, SC_SYSTEM_STATE)  & 0x3u);
    s->output_enable = (u8)(REG_RD(SC_BASE, SC_OUTPUT_ENABLE) & 0x7u);
    /* 레지스터는 100MHz clock count. UART 로 나가는 state_timer 는
     * ms 단위라 여기서 변환한다 (CLK_TO_MS, mission_ip_regs.h). */
    s->state_timer   = CLK_TO_MS(REG_RD(SC_BASE, SC_STATE_TIMER));
}

const char *SC_StateStr(u8 state)
{
    switch (state) {
        case ST_NORMAL:    return "NORMAL";
        case ST_WARNING:   return "WARNING";
        case ST_DEGRADED:  return "DEGRADED";
        case ST_SAFE_MODE: return "SAFE_MODE";
        default:           return "STATE_?";
    }
}

int SC_IsEnabled(void)
{
    return (s_sc_ctrl & SC_CTRL_ENABLE) ? 1 : 0;
}

/*
 * actuator_enable / control_valid 는 00 공통명세 9.3 레지스터 맵에 없어서
 * AXI 로 읽을 수 없다 (하드웨어 핀 -> LED5 / LED6 으로만 관측).
 * UART $MISSION 필드를 채우려고 C 의 core 출력 논리를 그대로 옮겨 유도한다.
 *
 *   always @(*) begin
 *       output_enable = 000; actuator_enable = 0; control_valid = 0;
 *       if (enable && fault_valid) case (state)
 *           NORMAL / WARNING / DEGRADED : actuator=1, control_valid=1
 *           SAFE_MODE                   : actuator=0, control_valid=0
 *   end
 *
 * 즉 enable 또는 fault_valid 가 0 이면 상태와 무관하게 0 이다.
 * fault_valid 는 fault_manager 의 enable 과 같다 (02_MEMBER_B 2장).
 * 보드 LED5/LED6 과 이 값이 일치하는지가 04 체크리스트 3장 T25 검증 항목이다.
 */
u8 SC_ActuatorEnable(u8 state, int enabled, int fault_valid)
{
    if (!enabled || !fault_valid)  return 0u;
    return (state == ST_SAFE_MODE) ? 0u : 1u;
}

u8 SC_ControlValid(u8 state, int enabled, int fault_valid)
{
    if (!enabled || !fault_valid)  return 0u;
    return (state == ST_SAFE_MODE) ? 0u : 1u;
}
