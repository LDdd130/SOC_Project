/******************************************************************************
 * main.c — 임무컴퓨터 상태 감시·고장 대응 SoC  MicroBlaze 통합 펌웨어
 *
 * 구성 (00 공통명세 2장)
 *   heartbeat_async ─▶ myip_heartbeat_monitor(A) ─timeout─▶ fault_manager(B)
 *                                                             │
 *                            fault_level/device/code/valid     ▼
 *                                                    safety_controller(C)
 *                                                             │
 *                                       system_state/output_enable/actuator
 *                                                             ▼
 *                                                     LED[15:0] / UART
 *
 * 하는 일
 *   1. 04 체크리스트 6장 부팅 순서 13단계를 순서대로 실행
 *   2. Heartbeat 생성 (실제 하위 장치 대체)
 *   3. 세 IP 의 IRQ 를 ISR 로 받고 메인 루프에서 $EVENT 로 보고
 *   4. PC 대시보드와 UART 프로토콜 송수신
 *
 * UART : AXI UARTLite 9600 8N1. 출력은 전부 ASCII.
 ******************************************************************************/

#include "platform.h"
#include "xil_printf.h"
#include "xil_exception.h"
#include "xstatus.h"
#include "sleep.h"

#include "mission_ip_regs.h"
#include "mission_intr.h"
#include "uart_proto.h"
#include "hb_gen.h"

/* ------------------------------------------------------------------ */
/* 시간 축                                                             */
/*                                                                     */
/* Block Design 에 AXI Timer 가 없다. BSP 는 MicroBlaze RISC-V 내부      */
/* Cycle Counter 로 usleep() 을 구현한다(XTIMER_DEFAULT_TIMER_IS_MB_RISCV,*/
/* XTIMER_NO_TICK_TIMER). 주기 인터럽트가 없으므로 메인 루프가 직접        */
/* ms 를 센다. 루프 본체 실행 시간만큼 실제보다 느리게 흐르지만            */
/* timestamp 는 표시용이라 문제되지 않는다.                              */
/* ------------------------------------------------------------------ */
#define TICK_MS             5u      /* 메인 루프 주기          */
#define MISSION_PERIOD_MS   500u    /* $MISSION 주기           */

/*
 * 9600bps 에서 한 글자가 약 1.04ms 다. $MISSION 한 줄이 60자를 넘으므로
 * 전송에만 60ms 이상 걸린다. README_PROTOCOL 권장 범위(100~500ms) 중
 * 가장 느린 값을 써야 링크가 포화되지 않는다.
 */

static u32 g_ms = 0;

/* ------------------------------------------------------------------ */
/* 변화 감지용 직전 상태                                                */
/*                                                                     */
/* $EVENT 의 인자는 ISR 이 IRQ 진입 시점에 떠 둔 Snapshot 에서 만든다    */
/* (00 공통명세 12장 "원인을 전역 변수/큐에 저장", "필요 시 상태          */
/* Snapshot 저장"). 12장이 ISR 에 금지하는 것은 문자열 출력·긴 Delay·    */
/* 전체 로그 출력이지 레지스터 조회가 아니다.                            */
/*                                                                     */
/* (2026-07-31 수정) 예전에는 메인 루프가 TICK_MS 마다 폴링해서 직전     */
/* 값과 비교했다. 그러면 폴링 주기(5ms)보다 짧은 상태가 통째로 사라진다. */
/* eval_tick 1ms × PERSIST_LIMIT=5 = 5ms 인 LEVEL_1(WARNING) 이 정확히   */
/* 그 경우라, 보드 로그에 STATE_CHANGE,WARNING 이 한 줄도 남지 않고      */
/* FAULT_CHANGE 가 level 0 -> 2 로 1 을 건너뛰었다. 하드웨어는 0 -> 1    */
/* 전이에도 IRQ 를 올리고 있었으므로(fault_manager_core.v out_changed),  */
/* 그 순간의 값을 ISR 에서 받아 두면 유지 시간과 무관하게 보고된다.      */
/*                                                                     */
/* 폴링은 IRQ 를 놓쳤을 때를 위한 백스톱으로만 남긴다. IRQ 경로 자체의   */
/* 동작은 진입 횟수로 따로 증명한다(04 체크리스트 5.2).                  */
/* ------------------------------------------------------------------ */
static u8 s_prev_level  = 0xFF;
static u8 s_prev_device = 0xFF;
static u8 s_prev_code   = 0xFF;
static u8 s_prev_state  = 0xFF;
static u8 s_prev_to     = 0x00;

static void boot_banner(void)
{
    xil_printf("\r\n\r\n");
    xil_printf("==================================================\r\n");
    xil_printf(" Mission SoC - MicroBlaze integrated firmware\r\n");
    xil_printf(" HB(A) base = 0x%08x\r\n", (unsigned)HB_BASE);
    xil_printf(" FM(B) base = 0x%08x\r\n", (unsigned)FM_BASE);
    xil_printf(" SC(C) base = 0x%08x\r\n", (unsigned)SC_BASE);
    xil_printf(" GPIO0=0x%08x (error/critical)  GPIO1=0x%08x (heartbeat)\r\n",
               (unsigned)GPIO0_BASE, (unsigned)GPIO1_BASE);
    xil_printf("==================================================\r\n");
}

/* ------------------------------------------------------------------ */
/* 04 체크리스트 6장 / 8장 : MicroBlaze 부팅 순서                        */
/*                                                                     */
/* (2026-07-30 수정) 예전에는 HB_Init()/FM_Init()/SC_Init() 를 순서대로  */
/* 불러서, 각 IP 가 "자기 자신만 Disable -> 설정 -> Clear" 를 마치고     */
/* 다음 IP로 넘어갔다. Cold Reset(전원 인가)이면 세 IP 가 리셋 직후라     */
/* 어차피 전부 Disable 상태라 문제가 없었지만, MicroBlaze 만 재시작하고  */
/* AXI 주변 IP 는 리셋되지 않는 상황(예: 디버거 CPU Reset)이면 얘기가    */
/* 다르다 — HB 를 재설정하는 동안 FM/SC 가 여전히 Enable 인 채로 HB 의   */
/* 과도기 출력(alive/timeout)을 계속 읽어 엉뚱한 Fault/State 이벤트를    */
/* 순간적으로 만들 수 있다. 그래서 04 체크리스트가 요구하는 대로         */
/*   세 IP 모두 Disable -> 세 IRQ 모두 Disable -> 전체 설정 -> 전체 Clear */
/*   -> INTC 등록 -> FM/SC Enable -> HB Enable -> IRQ Enable -> Global   */
/* 을 전역 단계로 명시적으로 분리한다. 개별 IP 의 레지스터 규칙(Shadow   */
/* CTRL, W1P 등)은 그대로 각 *_regs.c 의 공개 함수를 그대로 쓴다.        */
/* ------------------------------------------------------------------ */
static int boot_sequence(void)
{
    int st;

    /* 1~2. 세 IP 모두 Disable, 세 IRQ 모두 Disable (IP 하나라도 아직
     *      Enable 인 채로 다른 IP 를 재설정하는 창을 없앤다) */
    HB_Enable(0);
    FM_Enable(0);
    SC_Enable(0);
    HB_EnableIrq(0);
    FM_EnableIrq(0);
    SC_EnableIrq(0);

    /* GPIO 로 주입한 error/critical 은 CPU Reset 으로는 안 지워진다.
     * 8단계에서 FM_ResetFault() 가 항상 성공하려면(=device_fault 없음)
     * 설정을 시작하기 전에 여기서 먼저 지워야 한다. */
    INJ_ClearAll();

    /* 3~7. 전체 설정 (세 IP 다 Disable 된 상태에서만 진행) */
    HB_SetTimeout(0, MS_TO_CLK(CFG_TIMEOUT0_MS));
    HB_SetTimeout(1, MS_TO_CLK(CFG_TIMEOUT1_MS));
    HB_SetTimeout(2, MS_TO_CLK(CFG_TIMEOUT2_MS));
    /*
     * AUTO_RECOVER=1. 0 이면 Timeout Latch 가 CLEAR_ALL 전까지 안 풀려서
     * Heartbeat 를 다시 보내도 timeout 이 살아 있고, 04 체크리스트 4장
     * 시연 7단계 "모든 Fault 제거 -> Level 0 -> NORMAL" 이 성립하지 않는다.
     */
    HB_SetAutoRecover(1);
    FM_SetCriticalMask(CFG_CRITICAL_MASK);
    FM_SetPersistLimit(CFG_PERSIST_LIMIT);
    SC_SetRecoveryCount(CFG_RECOVERY_COUNT);
    SC_SetDegradeMask(CFG_DEGRADE_MASK);

    /* 8. 전체 Clear : Counter/Timeout/Fault Count 를 지우고 각 IRQ_STATUS
     *    를 W1C 한다. HB timeout 은 세 IP 가 아직 Disable 이라 0, error/
     *    critical 주입은 방금 INJ_ClearAll() 로 지웠으니 device_fault 가
     *    없다 -> FM_ResetFault() 는 항상 성공한다. */
    HB_ClearAll();
    HB_ClearIrq(HB_IRQ_ALL);
    FM_ResetFault();
    FM_ClearIrq(FM_IRQ_FAULT_CHANGE);
    SC_ClearIrq(SC_IRQ_STATE_CHANGE);

    HBGEN_Init();

    /* fault_manager 만 ID 레지스터가 있어 AXI 매핑을 직접 확인할 수 있다.
     * 여기서 실패하면 XSA 나 Address Editor 가 틀린 것이다. */
    if (FM_SelfCheck() != 0) {
        xil_printf("FATAL: fault_manager AXI mapping check failed\r\n");
        return -1;
    }

    /* 9. AXI INTC 초기화 및 Handler 등록 */
    st = MissionIntr_Init();
    if (st != XST_SUCCESS) {
        xil_printf("FATAL: AXI INTC init failed (%d)\r\n", st);
        return -1;
    }

    /* 10. Fault Manager 와 Safety Controller Enable
     *     (C 는 fault_valid=0 이면 출력을 안전값으로 강제하므로 B 가 먼저다) */
    FM_Enable(1);
    SC_Enable(1);

    /* 11. Heartbeat Monitor Enable */
    HB_Enable(1);

    /* 12. 각 IP IRQ Enable */
    FM_EnableIrq(1);
    HB_EnableIrq(1);
    SC_EnableIrq(1);

    /* 13. MicroBlaze Global Interrupt Enable */
    Xil_ExceptionEnable();

    xil_printf("Boot complete\r\n");
    return 0;
}

/* ------------------------------------------------------------------ */
/* 상태 변화 -> $EVENT                                                  */
/* ------------------------------------------------------------------ */
/*
 * 상태 한 벌을 직전 값과 비교해 바뀐 것만 $EVENT 로 내보낸다.
 * ISR Snapshot 과 폴링 백스톱이 같은 함수를 쓰므로, 폴링이 뒤늦게 같은
 * 값을 다시 들고 와도 아무것도 출력되지 않는다 (중복 방지).
 */
static void report_state(u8 hb_timeout, u8 fm_level, u8 fm_device,
                         u8 fm_code, u8 sc_state)
{
    u8 i;

    /* Heartbeat Timeout 은 장치별로 0 -> 1 이 된 것만 보고한다 */
    for (i = 0; i < 3; i++) {
        u8 bit = (u8)(1u << i);
        if ((hb_timeout & bit) && !(s_prev_to & bit)) {
            PROTO_SendEventHeartbeatTimeout(g_ms, i);
        }
    }
    s_prev_to = hb_timeout;

    /* 00 공통명세 8.5 : Level, Device, Code 중 하나만 바뀌어도 변화다 */
    if (fm_level  != s_prev_level  ||
        fm_device != s_prev_device ||
        fm_code   != s_prev_code) {
        PROTO_SendEventFaultChange(g_ms, fm_level, fm_device, fm_code);
        s_prev_level  = fm_level;
        s_prev_device = fm_device;
        s_prev_code   = fm_code;
    }

    if (sc_state != s_prev_state) {
        PROTO_SendEventStateChange(g_ms, SC_StateStr(sc_state));
        s_prev_state = sc_state;
    }
}

/*
 * ISR 이 남긴 Snapshot 을 들어온 순서대로 보고한다. 이게 짧은 상태를
 * 잡는 주 경로다. 큐 깊이만큼만 돌아 한 Tick 을 독점하지 않는다.
 */
static void drain_snapshots(void)
{
    static u32 s_drop_seen = 0;

    mission_snap_t s;
    u32 dropped;
    u32 n = 0;

    while (n < MISSION_SNAP_DEPTH && MissionIntr_TakeSnap(&s)) {
        report_state(s.hb_timeout, s.fm_level, s.fm_device,
                     s.fm_code, s.sc_state);
        n++;
    }

    /* Ring 이 넘쳤다는 건 한 Tick 안에 전이가 MISSION_SNAP_DEPTH 번 넘게
     * 일어났다는 뜻이다. 그러면 $EVENT 가 실제로 빠진 것이므로 조용히
     * 넘어가지 않고 알린다. 정상 동작에서는 나오지 않는다. */
    dropped = MissionIntr_SnapDropped();
    if (dropped != s_drop_seen) {
        s_drop_seen = dropped;
        PROTO_Printf("warn snapshot ring overflow dropped=%u\r\n",
                     (unsigned)dropped);
    }
}

/*
 * 폴링 백스톱. IRQ 가 하나도 없었는데 값이 달라져 있으면(있으면 안 되지만)
 * 여기서 잡는다. 평상시에는 값이 같아 아무것도 출력하지 않는다.
 */
static void report_changes(void)
{
    fm_status_t fm;
    sc_status_t sc;
    hb_status_t hb;

    FM_ReadStatus(&fm);
    SC_ReadStatus(&sc);
    HB_ReadStatus(&hb);

    report_state(hb.timeout, fm.level, fm.device, fm.code, sc.state);
}

/* ------------------------------------------------------------------ */
/* ISR 플래그 소비                                                      */
/*                                                                     */
/* 04 체크리스트 5.2 의 IRQ 전체 경로가 실제로 도는지 보여주는 부분이다.  */
/* 상태값 자체는 report_changes() 가 보고하므로 여기서는 경로가 살아      */
/* 있다는 사실만 남긴다.                                                */
/* ------------------------------------------------------------------ */
/*
 * 이 함수는 메인 루프 안에서 매 Tick 불린다. 그래서 여기서 xil_printf 를
 * 쓰면 IRQ 가 몰리는 순간(= 조작자가 GUI 버튼을 누르는 바로 그 순간)마다
 * 한 줄당 30ms 씩 블로킹하면서 RX FIFO 를 굶긴다. PROTO_Printf 는 글자마다
 * RX 를 Ring 으로 퍼담으므로 명령이 유실되지 않는다. (2026-07-30)
 *
 * flag 는 Counter 가 아니라 0/1 이다. 한 Tick 안에 같은 IP 의 IRQ 가 두 번
 * 들어오면 count 는 2 오르고 이 줄은 한 번만 나간다. 로그의 count 가 건너뛰는
 * 건 그래서지 UART 유실이 아니다. 값 자체는 Snapshot Ring 이 전부 받는다.
 */
static void drain_irq_flags(void)
{
    u32 cause;

    if (MissionIntr_Take(&g_fm_irq, &cause)) {
        HBGEN_Pump();
        PROTO_Printf("irq FM  status=0x%02x count=%u\r\n",
                     (unsigned)cause, (unsigned)g_fm_irq.count);
    }
    if (MissionIntr_Take(&g_hb_irq, &cause)) {
        HBGEN_Pump();
        PROTO_Printf("irq HB  status=0x%02x count=%u\r\n",
                     (unsigned)cause, (unsigned)g_hb_irq.count);
    }
    if (MissionIntr_Take(&g_sc_irq, &cause)) {
        HBGEN_Pump();
        PROTO_Printf("irq SC  status=0x%02x count=%u\r\n",
                     (unsigned)cause, (unsigned)g_sc_irq.count);
    }
}

/* ================================================================== */
int main(void)
{
    u32 next_mission = 0;

    init_platform();
    boot_banner();

    if (boot_sequence() != 0) {
        xil_printf("halted\r\n");
        while (1) { }
    }

    PROTO_SendMission(g_ms);

    while (1) {
        /* 1) Heartbeat 생성.
         *    시간 판정은 heartbeat_monitor 의 LAST_COUNTn(하드웨어)으로 한다.
         *    UART TX 로 루프가 수백 ms 멈춰도 경과 시간이 정확히 반영된다.
         *    uart_proto 의 출력 함수들도 각자 HBGEN_Pump() 를 먼저 부른다. */
        HBGEN_Pump();

        /* 2) PC 명령 수신. 9600bps 에서 1ms 에 한 글자 정도 들어오므로
         *    UARTLite 의 16바이트 RX FIFO 가 넘치지 않도록 매 Tick 비운다. */
        PROTO_PollRx(g_ms);

        /* 3) IRQ 경로 확인 (ISR 이 세운 플래그) */
        drain_irq_flags();

        /* 4) ISR Snapshot -> $EVENT (짧게 스쳐 간 상태까지 여기서 나온다) */
        drain_snapshots();

        /* 5) 폴링 백스톱 -> $EVENT */
        report_changes();

        /* 6) 주기 상태 보고 -> $MISSION */
        if ((s32)(g_ms - next_mission) >= 0) {
            PROTO_SendMission(g_ms);
            next_mission = g_ms + MISSION_PERIOD_MS;
        }

        usleep(TICK_MS * 1000u);
        g_ms += TICK_MS;
    }

    cleanup_platform();
    return 0;
}
