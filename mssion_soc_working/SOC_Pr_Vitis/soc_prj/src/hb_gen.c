/******************************************************************************
 * hb_gen.c — Heartbeat 생성기
 *
 * axi_gpio_1 CH1 -> myip_heartbeat_monitor.heartbeat_async[2:0]
 * 시간 기준   -> myip_heartbeat_monitor.LAST_COUNTn (하드웨어 경과 Clock)
 ******************************************************************************/

#include "hb_gen.h"
#include "mission_ip_regs.h"

static int s_enable[3];
static u32 s_period_clk[3];     /* Clock 단위로 보관. LAST_COUNT 와 직접 비교한다 */

void HBGEN_Init(void)
{
    s_enable[0] = 1;  s_period_clk[0] = MS_TO_CLK(CFG_HB_PERIOD0_MS);
    s_enable[1] = 1;  s_period_clk[1] = MS_TO_CLK(CFG_HB_PERIOD1_MS);
    s_enable[2] = 1;  s_period_clk[2] = MS_TO_CLK(CFG_HB_PERIOD2_MS);

    REG_WR(GPIO1_BASE, GPIO_CH1_DATA, 0u);
}

void HBGEN_SetDeviceEnable(u8 device, int on)
{
    if (device > 2) return;
    s_enable[device] = on ? 1 : 0;
}

int HBGEN_GetDeviceEnable(u8 device)
{
    if (device > 2) return 0;
    return s_enable[device];
}

void HBGEN_SetPeriodMs(u8 device, u32 ms)
{
    if (device > 2) return;
    s_period_clk[device] = MS_TO_CLK((ms == 0u) ? 1u : ms);
}

u32 HBGEN_GetPeriodMs(u8 device)
{
    if (device > 2) return 0;
    return s_period_clk[device] / (MISSION_CLK_HZ / 1000u);
}

/*
 * 주기가 된 장치를 모아 한 번에 High 를 쓰고 곧바로 Low 로 되돌린다.
 * AXI Write 두 번 사이가 수십 클럭이라 2FF Synchronizer 가 High 를 놓치지 않는다.
 *
 * 시간 판정은 소프트웨어 카운터가 아니라 heartbeat_monitor 의 LAST_COUNTn 으로
 * 한다. 소프트웨어가 UART TX 때문에 수백 ms 멈춰 있었어도 하드웨어 Counter 는
 * 계속 돌았으므로 복귀 즉시 밀린 Pulse 를 정확히 한 번 내보낸다.
 */
void HBGEN_Pump(void)
{
    u32 pulse = 0;
    u8  i;

    for (i = 0; i < 3; i++) {
        if (!s_enable[i]) continue;                 /* Timeout 주입 중인 장치는 건드리지 않는다 */
        if (HB_GetLastCount(i) >= s_period_clk[i]) {
            pulse |= (1u << i);
        }
    }

    if (pulse) {
        REG_WR(GPIO1_BASE, GPIO_CH1_DATA, pulse);
        REG_WR(GPIO1_BASE, GPIO_CH1_DATA, 0u);
    }
}
