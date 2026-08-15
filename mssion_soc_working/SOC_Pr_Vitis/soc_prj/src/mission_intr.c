/******************************************************************************
 * mission_intr.c — AXI INTC 초기화와 세 IP ISR
 *
 * 근거 : 00 공통명세 12장, 04 체크리스트 5.2 / 8장
 *
 * 검증할 경로 (04 체크리스트 5.2)
 *   IRQ_STATUS Set -> Custom IP irq High -> AXI INTC Pending
 *   -> XIntc Handler -> IRQ_STATUS W1C -> irq Low
 ******************************************************************************/

#include <stddef.h>     /* NULL */

#include "mission_intr.h"
#include "mission_ip_regs.h"

#include "xintc.h"
#include "xil_exception.h"

static XIntc s_intc;

intr_record_t g_fm_irq = { 0, 0, 0 };
intr_record_t g_hb_irq = { 0, 0, 0 };
intr_record_t g_sc_irq = { 0, 0, 0 };

/* ------------------------------------------------------------------ */
/* 상태 Snapshot Ring (mission_intr.h 참조)                            */
/* ------------------------------------------------------------------ */
static mission_snap_t s_snap[MISSION_SNAP_DEPTH];
static volatile u32   s_snap_head = 0;      /* ISR 이 쓴다   */
static volatile u32   s_snap_tail = 0;      /* 메인이 읽는다 */
static volatile u32   s_snap_drop = 0;

/*
 * ISR 안에서만 부른다.
 *
 * AXI Lite 읽기 12회뿐이고 UART 출력도 Delay 도 없다 (00 공통명세 12장이
 * 금지하는 것은 ISR 안의 문자열 출력 / 긴 Delay / 전체 로그 출력이다).
 * 100MHz MicroBlaze 에서 수 us 로 끝나므로 9600bps RX(문자당 1.04ms)를
 * 굶기지 않는다.
 *
 * 이미 검증된 *_regs.c 의 공개 접근자를 그대로 쓴다. Snapshot 에 필요한
 * 필드보다 몇 개 더 읽지만, 레지스터 주소를 여기서 다시 적어 두 곳이
 * 어긋나는 것보다 낫다.
 */
static void snap_push(void)
{
    fm_status_t fm;
    sc_status_t sc;
    hb_status_t hb;
    u32 next = (s_snap_head + 1u) % MISSION_SNAP_DEPTH;

    if (next == s_snap_tail) {      /* 가득 참 : 오래된 쪽을 지키고 버린다 */
        s_snap_drop++;
        return;
    }

    FM_ReadStatus(&fm);
    SC_ReadStatus(&sc);
    HB_ReadStatus(&hb);

    s_snap[s_snap_head].hb_timeout = hb.timeout;
    s_snap[s_snap_head].fm_level   = fm.level;
    s_snap[s_snap_head].fm_device  = fm.device;
    s_snap[s_snap_head].fm_code    = fm.code;
    s_snap[s_snap_head].sc_state   = sc.state;

    s_snap_head = next;
}

/* ------------------------------------------------------------------ */
/* ISR — 짧게. 원인 읽고, W1C 하고, Snapshot 남기고, 플래그만 세운다.   */
/*                                                                     */
/* W1C 를 Snapshot 보다 먼저 한다. 반대로 하면 Snapshot 을 뜨는 동안    */
/* 도착한 새 변화의 Pending 까지 같이 지워져 그 전이를 통째로 잃는다.   */
/* 지금 순서면 그런 변화는 Pending 을 다시 세워 ISR 이 한 번 더 돌고,   */
/* 값이 안 바뀐 중복 Snapshot 은 메인 루프가 걸러낸다.                  */
/* ------------------------------------------------------------------ */
static void FM_IsrHandler(void *ref)
{
    (void)ref;
    g_fm_irq.cause = FM_ReadIrqStatus();
    FM_ClearIrq(FM_IRQ_FAULT_CHANGE);
    snap_push();
    g_fm_irq.count++;
    g_fm_irq.flag = 1;
}

static void HB_IsrHandler(void *ref)
{
    (void)ref;
    g_hb_irq.cause = HB_ReadIrqStatus();
    HB_ClearIrq(g_hb_irq.cause);        /* 실제로 Set 된 비트만 W1C */
    snap_push();
    g_hb_irq.count++;
    g_hb_irq.flag = 1;
}

static void SC_IsrHandler(void *ref)
{
    (void)ref;
    g_sc_irq.cause = SC_ReadIrqStatus();
    SC_ClearIrq(SC_IRQ_STATE_CHANGE);
    snap_push();
    g_sc_irq.count++;
    g_sc_irq.flag = 1;
}

/* ------------------------------------------------------------------ */
int MissionIntr_Init(void)
{
    int st;

    st = XIntc_Initialize(&s_intc, INTC_BASE);
    if (st != XST_SUCCESS) return st;

    st = XIntc_Connect(&s_intc, INTR_ID_FM, (XInterruptHandler)FM_IsrHandler, NULL);
    if (st != XST_SUCCESS) return st;
    st = XIntc_Connect(&s_intc, INTR_ID_HB, (XInterruptHandler)HB_IsrHandler, NULL);
    if (st != XST_SUCCESS) return st;
    st = XIntc_Connect(&s_intc, INTR_ID_SC, (XInterruptHandler)SC_IsrHandler, NULL);
    if (st != XST_SUCCESS) return st;

    st = XIntc_Start(&s_intc, XIN_REAL_MODE);
    if (st != XST_SUCCESS) return st;

    XIntc_Enable(&s_intc, INTR_ID_FM);
    XIntc_Enable(&s_intc, INTR_ID_HB);
    XIntc_Enable(&s_intc, INTR_ID_SC);

    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XIntc_InterruptHandler,
                                 &s_intc);
    /* 04 체크리스트 6장 13단계 : Global Interrupt Enable 은 마지막이다.
     * 여기서 켜지 않고 main 이 순서대로 켠다. */
    return XST_SUCCESS;
}

int MissionIntr_Take(intr_record_t *rec, u32 *cause_out)
{
    int hit;

    Xil_ExceptionDisable();
    hit = (rec->flag != 0);
    if (hit) {
        if (cause_out) *cause_out = rec->cause;
        rec->flag = 0;
    }
    Xil_ExceptionEnable();

    return hit;
}

int MissionIntr_TakeSnap(mission_snap_t *out)
{
    int hit;

    Xil_ExceptionDisable();
    hit = (s_snap_tail != s_snap_head);
    if (hit) {
        if (out) *out = s_snap[s_snap_tail];
        s_snap_tail = (s_snap_tail + 1u) % MISSION_SNAP_DEPTH;
    }
    Xil_ExceptionEnable();

    return hit;
}

u32 MissionIntr_SnapDropped(void)
{
    return s_snap_drop;
}
