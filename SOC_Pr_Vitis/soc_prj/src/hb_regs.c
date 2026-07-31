/******************************************************************************
 * hb_regs.c — heartbeat_monitor_ip 드라이버  (팀원 A 담당 함수)
 *
 * 근거 : 00 공통명세 8.1(Core 제어), 8.2(A->B), 9.1(레지스터 맵),
 *        12.1(Disable 정책)
 *
 * CTRL Shadow 가 필요한 이유
 *   RTL 의 CTRL Write 는 다음과 같다.
 *     ctrl_reg <= apply_wstrb32(...) & 32'h0000_0005;
 *   즉 CTRL 에 Write 할 때마다 ENABLE(bit0) 과 AUTO_RECOVER(bit2) 가
 *   그 Write 데이터로 덮어써진다. CLEAR_ALL(bit1) 만 W1P 라 저장되지 않는다.
 *   따라서 CLEAR_ALL 을 쏘려고 0x2 만 쓰면 ENABLE 이 0 이 되어 IP 가 꺼진다.
 *   RW 비트를 Shadow 에 들고 있다가 항상 함께 실어 보낸다.
 ******************************************************************************/

#include "mission_ip_regs.h"

static u32 s_hb_ctrl = 0;   /* RW 비트(ENABLE, AUTO_RECOVER)만 보관 */

void HB_Init(u32 to0_clk, u32 to1_clk, u32 to2_clk)
{
    s_hb_ctrl = 0;
    REG_WR(HB_BASE, HB_CTRL, s_hb_ctrl);        /* 먼저 Disable (04 6장 1단계) */

    REG_WR(HB_BASE, HB_IRQ_EN, 0);              /* 04 6장 2단계 */

    REG_WR(HB_BASE, HB_TIMEOUT0, to0_clk);      /* 04 6장 3단계 */
    REG_WR(HB_BASE, HB_TIMEOUT1, to1_clk);
    REG_WR(HB_BASE, HB_TIMEOUT2, to2_clk);

    /*
     * AUTO_RECOVER=1 로 둔다.
     * 0 이면 Timeout Latch 가 CLEAR_ALL 전까지 안 풀려서 Heartbeat 를 다시
     * 보내도 timeout 이 살아 있고, 04 체크리스트 4장 시연 7단계
     * "모든 Fault 제거 -> Level 0 -> NORMAL" 이 성립하지 않는다.
     * 00 공통명세 9.1 이 CTRL.bit2 로 정의한 정식 기능이다.
     */
    s_hb_ctrl |= HB_CTRL_AUTO_RECOVER;
    REG_WR(HB_BASE, HB_CTRL, s_hb_ctrl);

    HB_ClearAll();                              /* 04 6장 8단계 */
    HB_ClearIrq(HB_IRQ_ALL);
}

void HB_Enable(int on)
{
    if (on) s_hb_ctrl |=  HB_CTRL_ENABLE;
    else    s_hb_ctrl &= ~HB_CTRL_ENABLE;
    REG_WR(HB_BASE, HB_CTRL, s_hb_ctrl);
}

void HB_SetAutoRecover(int on)
{
    if (on) s_hb_ctrl |=  HB_CTRL_AUTO_RECOVER;
    else    s_hb_ctrl &= ~HB_CTRL_AUTO_RECOVER;
    REG_WR(HB_BASE, HB_CTRL, s_hb_ctrl);
}

/* W1P. Counter 와 Timeout 상태만 Clear 한다. IRQ Pending 은 건드리지 않는다
 * (00 공통명세 12.1). */
void HB_ClearAll(void)
{
    REG_WR(HB_BASE, HB_CTRL, s_hb_ctrl | HB_CTRL_CLEAR_ALL);
}

void HB_SetTimeout(u8 device, u32 clocks)
{
    switch (device) {
        case 0: REG_WR(HB_BASE, HB_TIMEOUT0, clocks); break;
        case 1: REG_WR(HB_BASE, HB_TIMEOUT1, clocks); break;
        case 2: REG_WR(HB_BASE, HB_TIMEOUT2, clocks); break;
        default: break;
    }
}

u32 HB_GetTimeout(u8 device)
{
    switch (device) {
        case 0: return REG_RD(HB_BASE, HB_TIMEOUT0);
        case 1: return REG_RD(HB_BASE, HB_TIMEOUT1);
        case 2: return REG_RD(HB_BASE, HB_TIMEOUT2);
        default: return 0;
    }
}

u32 HB_GetLastCount(u8 device)
{
    switch (device) {
        case 0: return REG_RD(HB_BASE, HB_LAST_COUNT0);
        case 1: return REG_RD(HB_BASE, HB_LAST_COUNT1);
        case 2: return REG_RD(HB_BASE, HB_LAST_COUNT2);
        default: return 0;
    }
}

void HB_EnableIrq(int on)
{
    REG_WR(HB_BASE, HB_IRQ_EN, on ? HB_IRQ_ALL : 0u);
}

u32 HB_ReadIrqStatus(void)
{
    return REG_RD(HB_BASE, HB_IRQ_STATUS) & HB_IRQ_ALL;
}

u32 HB_ReadIrqEn(void)
{
    return REG_RD(HB_BASE, HB_IRQ_EN) & HB_IRQ_ALL;
}

void HB_ClearIrq(u32 mask)
{
    REG_WR(HB_BASE, HB_IRQ_STATUS, mask & HB_IRQ_ALL);
}

void HB_ReadStatus(hb_status_t *s)
{
    u32 st = REG_RD(HB_BASE, HB_STATUS);

    s->alive         = (u8)( st        & 0x7u);
    s->timeout       = (u8)((st >> 8)  & 0x7u);
    s->last_count[0] = REG_RD(HB_BASE, HB_LAST_COUNT0);
    s->last_count[1] = REG_RD(HB_BASE, HB_LAST_COUNT1);
    s->last_count[2] = REG_RD(HB_BASE, HB_LAST_COUNT2);
}
