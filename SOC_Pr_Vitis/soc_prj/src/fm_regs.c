/******************************************************************************
 * fm_regs.c — fault_manager_ip 드라이버 및 상태 해석 함수  (팀원 B)
 *
 * 근거 : 00 공통명세 9.2(레지스터 맵), 10장(Fault 정책), 12.1(Disable 정책)
 *        02_MEMBER_B 6.1(RESET_FAULT), 6.2(Disable 출력)
 *
 * 보드 단독 브링업(sw/main.c)에서 39개 체크 전부 통과한 코드를 통합용으로
 * 옮긴 것이다. Offset 정의는 mission_ip_regs.h 로 이동했고 base 인자는
 * 매크로로 고정했다. 동작은 동일하다.
 ******************************************************************************/

#include "mission_ip_regs.h"

/* CTRL 은 RW(ENABLE) 와 W1P(RESET_FAULT) 가 섞여 있으므로
 * RW 비트를 로컬에 들고 있다가 항상 함께 써준다. */
static u32 s_fm_ctrl = 0;

int FM_SelfCheck(void)
{
    if (REG_RD(FM_BASE, FM_ID) != FM_ID_VALUE) return -1;

    /* RW 레지스터 하나로 AXI 쓰기/읽기가 모두 도는지 확인 후 원복 */
    {
        u32 saved = REG_RD(FM_BASE, FM_PERSIST_LIMIT);
        REG_WR(FM_BASE, FM_PERSIST_LIMIT, 0x5Au);
        if ((REG_RD(FM_BASE, FM_PERSIST_LIMIT) & 0xFFu) != 0x5Au) return -2;
        REG_WR(FM_BASE, FM_PERSIST_LIMIT, saved);
    }
    return 0;
}

void FM_Init(u32 critical_mask, u32 persist_limit)
{
    s_fm_ctrl = 0;
    REG_WR(FM_BASE, FM_CTRL, s_fm_ctrl);                    /* 04 6장 1단계 */

    REG_WR(FM_BASE, FM_IRQ_EN, 0);                          /* 04 6장 2단계 */
    REG_WR(FM_BASE, FM_CRITICAL_MASK, critical_mask & 0x7u);/* 04 6장 4단계 */
    REG_WR(FM_BASE, FM_PERSIST_LIMIT, persist_limit & 0xFFu);/*04 6장 5단계 */

    FM_ResetFault();                                        /* 04 6장 8단계 */
    REG_WR(FM_BASE, FM_IRQ_STATUS, FM_IRQ_FAULT_CHANGE);
}

void FM_Enable(int on)
{
    if (on) s_fm_ctrl |=  FM_CTRL_ENABLE;
    else    s_fm_ctrl &= ~FM_CTRL_ENABLE;
    REG_WR(FM_BASE, FM_CTRL, s_fm_ctrl);
}

/* W1P. 현재 Fault 가 하나라도 있으면 IP 가 무시한다.
 * Fault 가 모두 없을 때만 Count 와 IRQ Pending 을 Clear 한다 (02 문서 6.1). */
void FM_ResetFault(void)
{
    REG_WR(FM_BASE, FM_CTRL, s_fm_ctrl | FM_CTRL_RESET_FAULT);
}

void FM_SetCriticalMask(u32 mask)
{
    REG_WR(FM_BASE, FM_CRITICAL_MASK, mask & 0x7u);
}

void FM_SetPersistLimit(u32 value)
{
    REG_WR(FM_BASE, FM_PERSIST_LIMIT, value & 0xFFu);
}

void FM_EnableIrq(int on)
{
    REG_WR(FM_BASE, FM_IRQ_EN, on ? FM_IRQ_FAULT_CHANGE : 0u);
}

u32 FM_ReadIrqStatus(void)
{
    return REG_RD(FM_BASE, FM_IRQ_STATUS) & FM_IRQ_FAULT_CHANGE;
}

u32 FM_ReadIrqEn(void)
{
    return REG_RD(FM_BASE, FM_IRQ_EN) & FM_IRQ_FAULT_CHANGE;
}

void FM_ClearIrq(u32 mask)
{
    REG_WR(FM_BASE, FM_IRQ_STATUS, mask);
}

void FM_ReadStatus(fm_status_t *s)
{
    u32 in  = REG_RD(FM_BASE, FM_FAULT_INPUT);
    u32 cnt = REG_RD(FM_BASE, FM_FAULT_COUNT);

    s->level          = (u8)(REG_RD(FM_BASE, FM_FAULT_LEVEL)  & 0x3u);
    s->device         = (u8)(REG_RD(FM_BASE, FM_FAULT_DEVICE) & 0x3u);
    s->code           = (u8)(REG_RD(FM_BASE, FM_FAULT_CODE)   & 0xFFu);

    s->timeout        = (u8)( in        & 0x7u);
    s->error_flag     = (u8)((in >>  8) & 0x7u);
    s->critical_fault = (u8)((in >> 16) & 0x7u);

    s->count[0]       = (u8)( cnt        & 0xFFu);
    s->count[1]       = (u8)((cnt >>  8) & 0xFFu);
    s->count[2]       = (u8)((cnt >> 16) & 0xFFu);
}

/*
 * device_fault = timeout | error_flag | critical_fault  (00 공통명세 10장)
 * RESET_FAULT 를 보내기 전에 PC 로 $ERR,RESET_FAULT,FAULT_ACTIVE 를 돌려주려고
 * 소프트웨어에서도 같은 판정을 한다. IP 의 판정이 최종이다.
 */
int FM_HasActiveFault(void)
{
    u32 in = REG_RD(FM_BASE, FM_FAULT_INPUT);
    u32 df = ( in        & 0x7u)
           | ((in >>  8) & 0x7u)
           | ((in >> 16) & 0x7u);
    return (df != 0u);
}

/* fault_valid 는 Level 신호이고 enable 과 같다 (02_MEMBER_B 2장).
 * AXI 로 따로 읽을 수 있는 비트가 없어서 Shadow 로 답한다. */
int FM_IsEnabled(void)
{
    return (s_fm_ctrl & FM_CTRL_ENABLE) ? 1 : 0;
}

const char *FM_LevelStr(u8 level)
{
    switch (level) {
        case FM_LEVEL_0_NORMAL:   return "LEVEL_0_NORMAL";
        case FM_LEVEL_1_WARNING:  return "LEVEL_1_WARNING";
        case FM_LEVEL_2_DEGRADED: return "LEVEL_2_DEGRADED";
        case FM_LEVEL_3_SAFE:     return "LEVEL_3_SAFE";
        default:                  return "LEVEL_?";
    }
}

const char *FM_CodeStr(u8 code)
{
    switch (code) {
        case FM_FAULT_NONE:         return "FAULT_NONE";
        case FM_FAULT_TIMEOUT:      return "FAULT_TIMEOUT";
        case FM_FAULT_ERROR_CODE:   return "FAULT_ERROR_CODE";
        case FM_FAULT_CRITICAL:     return "FAULT_CRITICAL";
        case FM_FAULT_MULTI_DEVICE: return "FAULT_MULTI_DEVICE";
        case FM_FAULT_RECOVERY_REQ: return "FAULT_RECOVERY_REQUIRED";
        default:                    return "FAULT_?";
    }
}

const char *FM_DeviceStr(u8 device)
{
    switch (device) {
        case FM_DEVICE_0:         return "DEVICE_0";
        case FM_DEVICE_1:         return "DEVICE_1";
        case FM_DEVICE_2:         return "DEVICE_2";
        case FM_MULTIPLE_OR_NONE: return "MULTIPLE_OR_NONE";
        default:                  return "DEVICE_?";
    }
}

/* ================================================================== */
/* Fault Injection — 외부 입력 대체 (00 공통명세 8.3)                   */
/*                                                                     */
/* 실제 장치가 없으므로 error_flag / critical_fault 는 AXI GPIO 로       */
/* 주입한다. 04 체크리스트 5.1 이 요구하는 2FF Synchronizer 는 보드       */
/* 스위치를 붙일 때 필요한 것이고, GPIO 는 이미 AXI Clock 동기 출력이라   */
/* 추가 동기화가 필요 없다.                                             */
/*                                                                     */
/* timeout 은 여기에 없다. A 의 heartbeat_monitor 가 만든다.            */
/* ================================================================== */

static u32 s_err_mask  = 0;
static u32 s_crit_mask = 0;

void INJ_SetError(u32 mask3)
{
    s_err_mask = mask3 & 0x7u;
    REG_WR(GPIO0_BASE, GPIO_CH1_DATA, s_err_mask);
}

void INJ_SetCritical(u32 mask3)
{
    s_crit_mask = mask3 & 0x7u;
    REG_WR(GPIO0_BASE, GPIO_CH2_DATA, s_crit_mask);
}

u32 INJ_GetError(void)    { return s_err_mask;  }
u32 INJ_GetCritical(void) { return s_crit_mask; }

void INJ_ClearAll(void)
{
    INJ_SetError(0);
    INJ_SetCritical(0);
}
